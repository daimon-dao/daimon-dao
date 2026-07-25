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

The frontend in `daimon-dapp/` carries open npm advisories that Dependabot
reports on this repository. They are listed here so a reviewer does not have to
re-derive the analysis. **None of them affects the contracts**, which have no
npm dependencies at runtime.

What matters for the assessment: the dApp server is a **stateless public
frontend**. It holds no keys, no funds, no database and no authenticated
sessions; it never signs anything. All chain interaction happens client-side in
the user's browser through their own wallet. The worst realistic outcome of a
frontend compromise or outage is that the page is unavailable — users can
always interact with the contracts directly via BscScan or `cast`.

**Fixed** (overrides in `daimon-dapp/package.json`): `axios` ≥1.18.0,
`postcss` ≥8.5.23, `ws` ≥8.21.1. The `ws` override alone cleared the whole
WalletConnect / reown / viem chain, which was flagged only through that
transitive dependency.

**Open, accepted:**

| Advisory | Why it stays open | Why it is not exploitable here |
|---|---|---|
| `next` 14.2.35 — several DoS / SSRF / cache-poisoning / XSS advisories | No fix exists in the 14.x line (14.2.35 is the last release); the fixed versions are 15.5.21+ / 16.x, a framework major upgrade. Deferred: it would destabilise a working dApp for no security gain here. | Every advisory requires a feature this app does not use. It has **no middleware, no Server Actions, no route handlers, no rewrites, no i18n routing, no `next/image`, no `images.remotePatterns`, no CSP nonces and no custom server** — `next.config.mjs` sets only `reactStrictMode`. The residue is DoS against server-side rendering of public, read-only pages. |
| `uuid` <11.1.1 (via `@metamask/sdk` and the MetaMask utils chain) | The fix is uuid 11.x, a major bump forced onto MetaMask packages that expect the v8/v9 API — a real risk of breaking wallet connection. | The advisory is a missing bounds check in `v3`/`v5`/`v6` **when the caller passes a `buf` argument**. The MetaMask SDK uses `uuid.v4()` for request ids and never passes a buffer, so the vulnerable path is not reached. |
| `@metamask/sdk`, `@metamask/utils`, `@metamask/rpc-errors`, `@metamask/sdk-communication-layer`, `@gemini-wallet/core`, `@wagmi/connectors`, `wagmi` | Flagged transitively because of the `uuid` entry above; they have no advisory of their own. Clearing them would mean `wagmi@3`, a major upgrade of the wallet layer. | Same as `uuid`: the vulnerable code path is never executed. |

Re-check with `npm audit` inside `daimon-dapp/`. Note that `npm audit` counts
one entry per affected package in the tree, so its totals are higher than the
number of distinct advisories.

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
