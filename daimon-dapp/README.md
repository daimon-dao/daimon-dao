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
| `NEXT_PUBLIC_CHAIN_ID` | `97` | `97` = BSC testnet, `56` = BSC mainnet |
| `NEXT_PUBLIC_WC_PROJECT_ID` | empty | WalletConnect Cloud project id. Optional: without it, only MetaMask/Trust (injected) remain. |

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

## Switching chain (testnet → mainnet)

Everything in **one file**: [src/config/contracts.ts](src/config/contracts.ts).

1. Fill in `BSC_MAINNET` with the mainnet deploy addresses (including the
   PancakeSwap pair, read it from `daimonV2.uniswapV2Pair()`).
2. Set `NEXT_PUBLIC_CHAIN_ID=56`.

No other file needs touching: RPC, explorer and the wagmi chain follow in
cascade.

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

For the mainnet launch: same procedure + `NEXT_PUBLIC_CHAIN_ID=56` and mainnet
addresses in contracts.ts (see above).

## Operational notes

- The staking positions list scans locks by id (up to 400): on mainnet with
  many stakers an event indexer will be needed (phase 2).
- Countdowns use the browser clock; the "real" state is always re-checked
  on-chain by the contracts at transaction time.
- No tracker/analytics. No sensitive data in localStorage (only the theme
  preference).
