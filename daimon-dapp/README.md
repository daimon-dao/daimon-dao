# Daimon dApp

Official Daimon DAO frontend: on-chain dashboard, 1:1 migration, vote-escrow
staking and governance. Next.js 14 (App Router) + TypeScript + TailwindCSS +
wagmi v2/viem. Static build compatible with Vercel.

It is a subfolder of the contracts monorepo (deliberate choice: the ABIs are
generated directly from the Foundry artifacts in `../out`, same git history,
no risk of mismatched ABIs).

## Local setup

```sh
cd daimon-dapp
npm install
npm run abis        # generates src/config/abis/ from the Foundry artifacts (../out)
npm run dev         # http://localhost:3000
```

If you change the contracts: `forge build` in the root, then `npm run abis`.

## Environment variables

Copy `.env.example` to `.env.local`:

| Variable | Default | Notes |
|---|---|---|
| `NEXT_PUBLIC_CHAIN_ID` | `97` | `97` = BSC testnet, `56` = BSC mainnet. Build-time: a change needs a redeploy. |
| `NEXT_PUBLIC_WC_PROJECT_ID` | empty | WalletConnect Cloud project id. Optional: without it, only MetaMask/Trust (injected) remain. |

There are no other variables and there must never be a secret here: every
`NEXT_PUBLIC_*` value ships to the browser. The RPCs are public endpoints
(list in `RPC_URLS`, [src/config/contracts.ts](src/config/contracts.ts),
walked in order by viem's fallback transport); the WalletConnect metadata
always advertises `https://app.daimon.money` (`APP_URL`).

## Country restriction (dormant)

**The interface blocks no one**: `RESTRICTED_COUNTRIES`
([src/config/restricted.ts](src/config/restricted.ts)) is empty by decision
(2026-09-29), and DISCLAIMER_TERMS v0.3 §5 states that access is not
restricted by location. With the list empty,
[src/middleware.ts](src/middleware.ts) returns at its first line and no
request is affected, whatever headers it carries.

The mechanism stays so it can be switched on by editing that one constant:
a visitor whose `x-vercel-ip-country` (set by Vercel at its edge) is listed
then gets a plain EN/IT notice with HTTP 451 instead of the app — no app
code, no wallet, no RPC — while `/terms` and `/terms/it` stay readable.
Switching it on requires amending the terms' §5 in the same release. To test
locally, force the header:

```sh
curl -i -H "x-vercel-ip-country: IR" http://localhost:3000/
```

The contracts stay permissionless either way: any restriction would apply
to the interface only.

## Terms of use (acknowledgment)

Before any wallet interaction the dApp shows a plain summary of
DISCLAIMER_TERMS and requires an explicit "I understand and accept"
([src/components/TermsGate.tsx](src/components/TermsGate.tsx)). The
acceptance is stored only in the browser's localStorage (`daimon-terms`,
with the terms version): no cookie, nothing sent anywhere. The full text is
served at `/terms` (EN, authoritative) and `/terms/it`, generated from the
repository's `docs/DISCLAIMER_TERMS_v<version>_{EN,IT}.md`:

```sh
npm run terms       # regenerates src/content/terms.ts
```

A new terms version: bump `TERMS_VERSION` in `scripts/generate-terms.mjs`
and rerun — every visitor is asked to accept again.

## Languages (EN/IT)

The dApp is bilingual: **English (default) + Italian**. EN|IT selector in the
header; the choice persists in the `daimon-locale` cookie. On the first visit
with no cookie it starts in Italian only if that is the browser's primary
language (Accept-Language), otherwise English.

Implementation: lightweight dictionaries in `src/messages/{en,it}.json` + a
React provider ([src/components/LocaleProvider.tsx](src/components/LocaleProvider.tsx),
helper in [src/lib/i18n.ts](src/lib/i18n.ts)) — no i18n libraries. To
add/change text: same key in **both** files (the fallback is English; a
missing key shows up literally, so it is noticed immediately). On-chain data
and proposal descriptions are not translated; number formatting is identical
in both languages, dates and countdowns are localized.

## Chains (testnet / mainnet)

Everything in **one file**: [src/config/contracts.ts](src/config/contracts.ts).
Both address sets are filled in: `BSC_TESTNET` (97) and `BSC_MAINNET` (56,
the 2026-09-29 launch deploy, each address checked on chain against
`deployments/two-phase-56.json`). `NEXT_PUBLIC_CHAIN_ID` picks one at build
time; RPC, explorer and the wagmi chain follow in cascade.

The migration page opens by itself: it polls the old token for the fee
exemption of the Migration's treasury (on mainnet the Timelock, launch step
11b) and refuses to send a claim until it reads `true`, showing "the
migration opens shortly" instead. The deadline shown is the Migration's
`effectiveMigrationDeadline()`, read live.

Proposal status is always `Governor.state(id)` — never the struct's
`canceled` / `executed` / `queued` flags (see `phaseOf` in
[src/lib/governance.ts](src/lib/governance.ts)).

## Logo

The official logo (vector, from the .ai file) is in `public/logo.svg`, used by
[src/components/Logo.tsx](src/components/Logo.tsx). In dark mode the component
adds a thin gold ring (`dark:ring-oro/60`) because the logo's navy disc would
blend into the night-blue background.

Favicon and iOS icon are handled by Next's App Router conventions:
`src/app/icon.svg` (vector favicon) and `src/app/apple-icon.png` (180×180,
opaque night-blue square). To update the logo: regenerate these three files
(SVG via `pdftocairo -svg`, see repo history).

## Deploy on Vercel (staging)

The dApp is a subfolder of the monorepo: on Vercel set **Root Directory =
`daimon-dapp`**. The pages use dynamic rendering (wagmi cookies read
server-side), fully supported by Vercel — no extra configuration, no
`vercel.json`.

1. Push the monorepo to a **private GitHub repo**, then on
   [vercel.com](https://vercel.com) → *Add New → Project* → import the repo.
2. In *Configure Project*: Root Directory `daimon-dapp` (Edit → select the
   folder). Detected framework: Next.js; default build command and output.
3. *Environment Variables*: add `NEXT_PUBLIC_WC_PROJECT_ID` with the
   WalletConnect project id (required for the mobile QR; `.env.local` is not
   deployed). `NEXT_PUBLIC_CHAIN_ID` is not needed: the default is 97
   (testnet).
4. Deploy. The `*.vercel.app` URL is reachable but not indexed/linked. To make
   it truly private: *Settings → Deployment Protection → Vercel Authentication*
   (free) — requires a Vercel login to view the site. Note for mobile testing:
   open the URL in the phone browser (where you can log into Vercel), NOT in
   MetaMask's in-app browser; the wallet connection still goes through
   WalletConnect via deep link.
5. On WalletConnect Cloud, add the Vercel URL to the project's domain
   allowlist (WC project Settings), otherwise the relay may reject sessions
   from that domain.

For mainnet: same procedure + `NEXT_PUBLIC_CHAIN_ID=56` in the environment
(Production and/or Preview) that must run on chain 56. The variable is read at
build time: after changing it, redeploy.

## Operational notes

- The staking positions list scans locks by id (up to 400): on mainnet with
  many stakers an event indexer will be needed (phase 2).
- Countdowns use the browser clock; the "real" state is always re-checked
  on-chain by the contracts at transaction time.
- No tracker/analytics. No sensitive data in localStorage (only the theme
  preference and the terms acceptance with its version).
