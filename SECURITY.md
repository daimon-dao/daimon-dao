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

## Known dependency advisories (dApp)

*Last reviewed: 2026-08-13.*

The frontend in `daimon-dapp/` carries open npm advisories that Dependabot
reports on this repository. They are listed here so a reviewer does not have to
re-derive the analysis. **Every one of them is in the dApp — Next.js and its
dependency tree. Zero are in the Solidity contracts**, which have no npm
dependencies at all: they build with Foundry against `lib/` (OpenZeppelin) and
ship as bytecode. No npm advisory can reach them.

### Reading the alert count

Dependabot and `npm audit` report different totals for the same tree, and both
are correct: they count different things.

- **Dependabot counts one alert per advisory.** Next.js alone accounts for 21
  of them — one per CVE against a single installed version.
- **`npm audit` counts one entry per affected package** in the tree, so those
  same 21 Next.js advisories collapse into a single `next` entry.

After this review's fixes, `npm audit` reports **9 entries** (1 high,
8 moderate), resolving to **22 unique advisories**: `next` 21 and `uuid` 1.
Dependabot's figure will land near 22 once it reprocesses the lockfile; it
last reported 29 against the pre-fix tree.

The count had risen sharply from the ~5 reported in mid-2026. That was **not a
regression and not new exposure in our code**: the overrides below were in
place throughout and still effective. It was the sum of two effects —
Dependabot reprocessing the lockfile and surfacing the full Next.js advisory
set it had not yet expanded, plus three advisories published upstream in the
meantime (`hono`, `nanoid`, `socket.io-parser`), all three since fixed by the
overrides below. The per-advisory analysis is unchanged; only the arithmetic
moved.

What matters for the assessment: the dApp server is a **stateless public
frontend**. It holds no keys, no funds, no database and no authenticated
sessions; it never signs anything. All chain interaction happens client-side in
the user's browser through their own wallet. The worst realistic outcome of a
frontend compromise or outage is that the page is unavailable — users can
always interact with the contracts directly via BscScan or `cast`.

**Fixed** (overrides in `daimon-dapp/package.json`): `axios` ≥1.18.0,
`hono` ≥4.12.34, `nanoid` ≥3.3.18, `postcss` ≥8.5.23,
`socket.io-parser` ≥4.2.7, `ws` ≥8.21.1. All are within-major bumps of
transitive or build-time dependencies, so no user-facing behaviour changes.
The `ws` override alone cleared the whole WalletConnect / reown / viem chain,
which was flagged only through that transitive dependency; `hono`, `nanoid`
and `socket.io-parser` together removed 6 further advisories.

After each override round: `tsc --noEmit` clean, `next build` green on all
routes, the dev server renders live on-chain data, and both wallet connectors
(injected and WalletConnect) still initialise with a clean browser console.

**Open, accepted:**

| Advisory | Why it stays open | Why it is not exploitable here |
|---|---|---|
| `next` 14.2.35 — several DoS / SSRF / cache-poisoning / XSS advisories | No fix exists in the 14.x line (14.2.35 is the last release); the fixed versions are 15.5.21+ / 16.x, a framework major upgrade. Deferred: it would destabilise a working dApp for no security gain here. | Every advisory requires a feature this app does not use. It has **no middleware, no Server Actions, no route handlers, no rewrites, no i18n routing, no `next/image`, no `images.remotePatterns`, no CSP nonces and no custom server** — `next.config.mjs` sets only `reactStrictMode`. The residue is DoS against server-side rendering of public, read-only pages. |
| `uuid` <11.1.1 (via `@metamask/sdk` and the MetaMask utils chain) | The fix is uuid 11.x, a major bump forced onto MetaMask packages that expect the v8/v9 API — a real risk of breaking wallet connection. | The advisory is a missing bounds check in `v3`/`v5`/`v6` **when the caller passes a `buf` argument**. The MetaMask SDK uses `uuid.v4()` for request ids and never passes a buffer, so the vulnerable path is not reached. |
| `@metamask/sdk`, `@metamask/utils`, `@metamask/rpc-errors`, `@metamask/sdk-communication-layer`, `@gemini-wallet/core`, `@wagmi/connectors`, `wagmi` | Flagged transitively because of the `uuid` entry above; they have no advisory of their own. Clearing them would mean `wagmi@3`, a major upgrade of the wallet layer. | Same as `uuid`: the vulnerable code path is never executed. |

Re-check with `npm audit` inside `daimon-dapp/`. Note the two axes described
under *Reading the alert count*: `npm audit` totals are **lower** than
Dependabot's, because many advisories against one package collapse into a
single entry.

## Bug bounty

There is currently **no formal bug bounty program**: it will arrive with the
mainnet launch. Responsible reports received before launch will still be
publicly acknowledged in the advisory and — at the project's discretion — may
be rewarded retroactively when the program starts.

## Project status

Contracts deployed and verified on BSC **testnet**; test suite (unit + fuzz +
invariant) and Slither static analysis performed. **Not yet subjected to an
external professional audit.** The mainnet deploy will happen only after the
audit.
