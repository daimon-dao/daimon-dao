# Security Policy — Daimon DAO

This page explains how to report vulnerabilities responsibly. For the full
technical threat model (actors, defenses, known limits, trust assumptions)
see [THREAT_MODEL.md](THREAT_MODEL.md).

## How to report a vulnerability

If you think you have found a vulnerability in the contracts, the deploy
scripts, or the dApp, **do not open a public issue and do not disclose it**:
a vulnerability made public before it is fixed puts users' funds at risk.

Use the private GitHub channel, directly from this repository:

> **Security → Report a vulnerability** (Private Vulnerability Reporting)

The report reaches only the maintainers, who can discuss it with you
privately. Once fixed, we publish a coordinated advisory and — if you wish —
credit your contribution publicly.

### What to include

- a description of the issue and the affected contract/file;
- the estimated impact (funds at risk? governance? DoS?);
- reproduction steps — a Foundry PoC (`forge test`) is ideal;
- a suggested fix, if you have one.

## Response times

Actively maintained but by a small team; *best-effort* timelines:

| Step | Within |
|---|---|
| Acknowledgement of receipt | 72 hours |
| First assessment (severity, plan) | 7 days |
| Fix or mitigation for critical issues | as soon as possible, top priority |

We will keep you updated in the private thread at every step. In exchange we
ask for coordinated disclosure: no publication before the fix and the
advisory (we agree on the timing together).

## Scope

**In scope:** the contracts in `src/` (`DaimonV2`, `DaimonStaking`,
`DaimonGovernor`, `DaimonTimelock`, `DaimonMigration`), the deploy scripts in
`script/`, and the dApp (`daimon-dapp/`).

**Out of scope:** third-party sites, public RPCs, upstream dependencies
(report those to their respective projects — e.g. OpenZeppelin has its own
program on Immunefi), social engineering, and anything concerning the test
network only.

## IPFS mirror

The dApp also exists as a static mirror on IPFS, named by `daimon.blockchain`
(Unstoppable Domains, resolved by Brave and by the UD extension) and reachable
directly at `https://<cid>.ipfs.inbrowser.link/`; the current CID is in the
README's "Official channels". It is the same code as `app.daimon.money`,
built from the same commit, but it is served by IPFS gateways instead of a
server, so compared with the app it lacks:

- the response headers `Content-Security-Policy: frame-ancestors 'none'`,
  `X-Frame-Options: DENY` and `X-Content-Type-Options: nosniff` (a static file
  carries none): another page can frame the mirror and attempt clickjacking —
  the wallet's own confirmation prompt, outside the page, remains the control;
- WalletConnect: the mirror ships without a WalletConnect project id, so only
  injected wallets (browser extensions, wallets' in-app browsers) connect;
- an origin of its own on *path* gateways (`https://<gateway>/ipfs/<cid>/`):
  there every site served by that gateway shares one `localStorage`, so the
  terms acceptance, the language and wagmi's connection state are readable by
  other sites opened through the same gateway. The mirror shows a notice on
  such gateways; use the subdomain form (`https://<cid>.ipfs.<gateway>/`) or
  Brave's resolution, which give the site its own origin.

The mirror is identified by its content hash and anyone can rebuild it: check
out the commit named in the mirror's `mirror.json`, then in `daimon-dapp/`
run `npm ci && npm run build:ipfs`; the printed CID must equal the published
one (parameters and proof in [docs/IPFS_MIRROR.md](docs/IPFS_MIRROR.md)). A
page served under a different CID is not the project's mirror. Reports about
the mirror follow the same process as for the dApp.

## Known dependency advisories (dApp)

*Last reviewed: 2026-10-03 (Next 15 upgrade, branch `dapp/next15`).*

The frontend in `daimon-dapp/` carries open npm advisories that Dependabot
reports on this repository. They are listed here so a reviewer does not have to
re-derive the analysis. **Every one of them is in the dApp — Next.js and its
dependency tree. Zero are in the Solidity contracts**, which have no npm
dependencies at all: they build with Foundry against `lib/` (OpenZeppelin) and
ship as bytecode. No npm advisory can reach them.

### Reading the alert count

Dependabot and `npm audit` report different totals for the same tree, and both
are correct: they count different things.

- **Dependabot counts one alert per advisory.** Before the upgrade Next.js
  alone accounted for 23 of them — one per CVE against a single installed
  version.
- **`npm audit` counts one entry per affected package** in the tree, so those
  23 Next.js advisories collapsed into a single `next` entry, and today the
  single `braces` advisory shows up as 7 entries.

After the 2026-10-03 upgrade (Next 14.2.35 → 15.5.27, React 18 → 19),
`npm audit` reports **7 entries** (all high), resolving to **1 unique
advisory**: `braces` GHSA-vfj7-8cjw-p6xm, reached only through build-time
tooling (see *Open, accepted*). Before the upgrade it reported 32 entries
(1 critical, 8 high, 23 moderate): `next` alone carried 23 advisories, two of
them critical (unauthenticated RCE on Windows-hosted servers,
GHSA-p293-qw3h-jr36, and RCE in the image optimizer), all fixed in 15.5.24+.
Dependabot's figure will land near 1 once it reprocesses the lockfile.

The count had risen sharply during 2026. That was **not a regression and not
new exposure in our code**: it was Dependabot expanding the full Next.js
advisory set against one installed version, plus advisories published
upstream in the meantime. The per-advisory analysis of the Next 14 tree
(2026-10-02: only the Windows RCE applied, and only to local dev servers,
which were bound to 127.0.0.1 the same day) is superseded by the upgrade.

What matters for the assessment: the dApp server is a **stateless public
frontend**. It holds no keys, no funds, no database and no authenticated
sessions; it never signs anything. All chain interaction happens client-side in
the user's browser through their own wallet. The worst realistic outcome of a
frontend compromise or outage is that the page is unavailable — users can
always interact with the contracts directly via BscScan or `cast`.

**Fixed by the upgrade** (2026-10-03): `next` 15.5.27 (all 23 advisories),
`react` / `react-dom` 19 as Next 15 requires, `images.unoptimized: true` (the
optimizer was never used; now it is off), `browserslist` and
`baseline-browser-mapping` within-major updates.

**Fixed by overrides** in `daimon-dapp/package.json`, all within-major bumps
of transitive dependencies: `axios` ≥1.20.0, `hono` ≥4.13.7, `nanoid`
≥3.3.18, `postcss` ≥8.5.23, `socket.io-parser` ≥4.2.7, `ws` ≥8.21.1,
`@walletconnect/ethereum-provider` ≥2.25.0 (the version wagmi 2.19 pins,
2.21.1, carried the WalletConnect / reown advisories; 2.25.0 is the same
provider wagmi 3 ships and brings `@reown/appkit` 1.8.19, which also lifts the
`valtio` / `use-sync-external-store` React-18 peer), `uuid` ≥11.1.1 (one copy
in the tree now; the MetaMask SDK and utils only call `v4()`, which is
unchanged in 11.x, and this dApp never activates the MetaMask SDK connector).

After the upgrade: `tsc --noEmit` and `eslint .` clean, `next build` green
for chain 56 and 97, and on a local anvil fork of mainnet with a mock wallet:
migration approve + claim, staking approve + stake, propose + vote all
confirmed on chain; one-tap in-app connect (`eth_requestAccounts` only), the
WalletConnect modal on a mobile browser, the desktop extension path, 43 fresh
loads after wallet-cookie requests with no hydration error, no theme loss and
no foreign address.

**Open, accepted:**

| Advisory | Why it stays open | Why it is not exploitable here |
|---|---|---|
| `braces` ≤3.0.3 — stack exhaustion through deeply nested glob patterns (GHSA-vfj7-8cjw-p6xm), reported as 7 entries: `braces`, `micromatch`, `fast-glob`, `chokidar`, `tailwindcss` 3.4, `@next/eslint-plugin-next`, `eslint-config-next` | No patched `braces` release exists (3.0.3 is the latest); the only "fix" npm offers is Tailwind 4, a CSS-engine major rewrite that would not change the exposure. | `braces` only runs at build time, on glob patterns written by us: Tailwind's content scan and ESLint's file matching. It is not in the server bundle, not in the browser bundle, and never sees user input. |

The dApp still has **no Server Actions, no route handlers, no rewrites, no
i18n routing, no `next/image` and no custom server**; the middleware
(`src/middleware.ts`) is the region check, a no-op while the country list is
empty, and `next.config.mjs` sets the security headers
(`Content-Security-Policy: frame-ancestors 'none'`, `X-Frame-Options: DENY`,
`X-Content-Type-Options: nosniff`), re-verified after the upgrade.

Re-check with `npm audit` inside `daimon-dapp/`. Note the two axes described
under *Reading the alert count*: `npm audit` totals are **lower** than
Dependabot's, because many advisories against one package collapse into a
single entry.

## Past issues

### 2026-10-02 — dApp: a visitor's wallet address could appear in another visitor's page (fixed)

From the mainnet launch until 2 October 2026, the dApp's server
shared one wallet-library state across requests. After a visit with
a connected wallet, the next visitor's page could be rendered with
that wallet's address in the staking panel, until the browser
re-rendered it. No funds, keys or signatures were ever exposed — a
wallet address is public on-chain — but it could reveal that a given
address had visited the dApp. Found during an internal check,
reproduced, fixed (a separate state per request) and verified in
production on 2 October 2026. The smart contracts were not involved.

## Bug bounty

A bug bounty funded by the treasury will be proposed to governance. Until
then, responsible disclosure is welcome and will be credited publicly.

## Project status

Live on BNB Smart Chain **mainnet** since 2026-09-29: the audited code,
deployed unchanged and verified; addresses in the [README](README.md#mainnet-addresses),
every launch transaction in the
[mainnet launch record](docs/MAINNET_LAUNCH_RECORD.md). Test suite (unit +
fuzz + invariant + adversarial, **203 tests green**) and Slither static
analysis performed.
**External audit by Zenith complete** — the [full report](https://github.com/zenith-security/reports/blob/main/reports/Daimon%20DAO%20-%20Zenith%20Audit%20Report.pdf)
is published and the audited code range is frozen at tag
[`audit-final`](https://github.com/daimon-dao/daimon-dao/releases/tag/audit-final).
