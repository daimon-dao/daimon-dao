# Daimon dApp

Frontend ufficiale Daimon DAO: dashboard on-chain, migrazione 1:1, staking
vote-escrow e governance. Next.js 14 (App Router) + TypeScript + TailwindCSS
+ wagmi v2/viem. Build statica compatibile con Vercel.

È una sottocartella del monorepo dei contratti (scelta motivata: gli ABI
vengono generati direttamente dagli artifact Foundry in `../out`, stessa
storia git, nessun rischio di ABI disallineati).

## Setup locale

```sh
cd daimon-dapp
npm install
npm run abis        # genera src/config/abis/ dagli artifact Foundry (../out)
npm run dev         # http://localhost:3000
```

Se cambi i contratti: `forge build` nella root, poi `npm run abis`.

## Variabili d'ambiente

Copia `.env.example` in `.env.local`:

| Variabile | Default | Note |
|---|---|---|
| `NEXT_PUBLIC_CHAIN_ID` | `97` | `97` = BSC testnet, `56` = BSC mainnet |
| `NEXT_PUBLIC_WC_PROJECT_ID` | vuoto | Project id WalletConnect Cloud. Facoltativo: senza, restano MetaMask/Trust (injected). |

## Cambiare chain (testnet → mainnet)

Tutto in **un solo file**: [src/config/contracts.ts](src/config/contracts.ts).

1. Compila `BSC_MAINNET` con gli indirizzi del deploy mainnet (inclusa la
   pair PancakeSwap, leggila da `daimonV2.uniswapV2Pair()`).
2. Imposta `NEXT_PUBLIC_CHAIN_ID=56`.

Nessun altro file va toccato: RPC, explorer e chain wagmi seguono a cascata.

## Logo

Il logo ufficiale (vettoriale, dal file .ai) è in `public/logo.svg`, usato
da [src/components/Logo.tsx](src/components/Logo.tsx). In dark mode il
componente aggiunge un anello oro sottile (`dark:ring-oro/60`) perché il
disco navy del logo si fonderebbe con lo sfondo blu notte.

Favicon e icona iOS sono gestite dalle convenzioni App Router di Next:
`src/app/icon.svg` (favicon vettoriale) e `src/app/apple-icon.png`
(180×180, quadrato blu notte opaco). Per aggiornare il logo: rigenerare
questi tre file (SVG via `pdftocairo -svg`, vedi storia del repo).

## Note operative

- La lista posizioni di staking scansiona i lock per id (fino a 400): su
  mainnet con molti staker servirà un indexer di eventi (fase 2).
- I countdown usano l'orologio del browser; lo stato "vero" è sempre
  ricontrollato on-chain dai contratti al momento della transazione.
- Nessun tracker/analytics. Nessun dato sensibile in localStorage (solo la
  preferenza del tema).
