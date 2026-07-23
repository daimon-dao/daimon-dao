# DAPP_SPEC.md — Daimon (DMN) dApp specification

Complete specification for building the dApp. To be read together with the
contracts repository (already deployed and verified on BSC testnet) and
TESTNET_RESULTS.md for the addresses.

---

## 1. Technical stack

```
Framework:         Next.js 14+ (App Router) + TypeScript
Styling:           TailwindCSS
Wallet/chain:      wagmi v2 + viem (NO web3.js, NO ethers)
Supported wallets: MetaMask, WalletConnect, Trust Wallet (via wagmi connectors)
Chain:             BSC testnet (97) now, BSC mainnet (56) prepared
                   → chain config and contract addresses in a single file
                     src/config/contracts.ts with a chainId switch
Frontend deploy:   static build compatible with Vercel
```

The testnet contract addresses are in the repo (TESTNET_RESULTS.md / the
deploy broadcast JSON). The ABIs must be generated from the Foundry artifacts
(out/) — do not copy them by hand.

## 2. Design system

```
THEME: dark mode by default (night blue), light mode available via toggle.

Brand colors:
  Night blue (main bg):        #0a1128
  Light night blue (card):     #111b3a
  Borders:                     #2a3655
  Gold (accent, CTA, values):  #c9a227
  Light gold (title text):     #f5e9c8
  Secondary text:              #8a94ad
  Green (success/governance):  #5dcaa5
  Red (errors only):           #e24b4a

Light mode: same gold accents, white/warm-light-gray surfaces, night-blue
text.

Font: clean sans-serif (Inter or similar). Important numbers: 500 weight.
NO heavy gradients, NO neon effects. Sober, professional, "Swiss crypto bank".

LOGO: not yet available. Prepare a <Logo /> component used in the header and
favicon that for now shows a circle with a dashed gold border and the text
"LOGO"; it will be replaced with the final file (PNG/SVG) when provided. Plan
for the final file to go in /public/logo.svg.
```

## 3. Page structure

```
/            Dashboard (home)
/migrazione  1:1 migration from the old Daimon
/staking     Stake, positions, rewards
/governance  Proposals, voting, queue/execute
```

Persistent header: logo + DAIMON name, nav (Dashboard, Migration, Staking,
Governance), a Connect wallet button (gold). Sober footer with links to the
contracts on BscScan.

## 4. Dashboard (home) — project priority

Works EVEN without a connected wallet (all public on-chain reads).

**Metric cards (grid of 4):**
1. Current supply (totalSupply, formatted e.g. "987.4B DMN")
2. Tokens burned (INITIAL_SUPPLY - totalSupply) with the subtitle "towards the
   21B floor"
3. Total staked (totalStakedAmount from staking) with % of supply
4. DMN price + market cap — SOBER NUMBER:
   - only the current value, NO 24h % change, NO green/red arrows, NO charts
     (explicit owner decision)
   - primary source: on-chain read of the PancakeSwap pair reserves
     (getReserves → price in BNB → USD via BNB price from a public API)
   - fallback: DexScreener API
   - on testnet: show "n/a (testnet)" if the pool has no sensible liquidity

**Deflation bar (central element, full width):**
- Progress from 1000B toward 21B, gold fill
- Labels: "1000B → 21B", the amount burned
- Below, the key sentence always visible:
  "Once the floor is reached, 100% of the revenue will go to stakers"

**Quick-access cards (2):**
- "Your staking" → if the wallet is not connected: "Connect your wallet to see
  positions and rewards" (NEVER show fake zeros)
- Most recent governance proposal with state and countdown → link to
  /governance

**Verifiability:** each metric card has a small icon/link that opens the
relevant contract on BscScan (testnet.bscscan.com for chain 97).

**"Buy DMN" button** (added 2026-07-19): in the price card, a gold button that
opens PancakeSwap with `outputCurrency` = the DMN address taken from
contracts.ts (never hardcoded: on mainnet it follows the new address on its
own). It is NOT an integrated swap — just a link, to bring the user to the
official pool and protect them from fake tokens. Below the button: a
copyable truncated address with an invitation to verify it. On chain 97 the
button is disabled with a tooltip ("PancakeSwap does not offer a testnet swap
UI"), ready for chain 56. A discreet secondary link in the footer (mainnet
only). No referral/tracking parameters in the URL.

## 5. Migration — a guided path, not a form

A 3-step visual wizard:

```
1. CONNECT     → wallet connect; automatically detects the user's balance of
                 old Daimon and shows it
2. APPROVE     → "Approve the migration" button (approve on the old token
                 towards DaimonMigration, amount = detected balance,
                 editable). Visible tx state (pending/confirmed).
3. RECEIVE DMN → "Migrate now" button (claim). On success: a confirmation
                 screen with the amount of DMN received 1:1 and a link to the
                 tx.
```

- Show the migration deadline (migrationDeadline) with a countdown.
- If the deadline has passed: a clear message, wizard disabled.
- Errors translated into understandable language (e.g. AmountMismatch → "The
  contract detected a mismatch in the amounts. Try again or contact support —
  your funds have not been touched.")
- Zero technical jargon in the labels.

## 6. Staking — with a simulator

**Simulator (top part, works even without a wallet):**
- Amount slider + lock selection (30/90/180/365 days from the on-chain
  lockOptions, with the real 1x/1.5x/2.2x/4x multipliers)
- Live preview: "You will get X voting power" + ≈ $ value of the amount
- Unlock date computed and shown in the clear

**Stake action:** approve (if needed) + stake, with clear tx states.

**Your positions (connected wallet):**
- List of locks: amount, multiplier, voting power, unlock date, countdown,
  a "Withdraw" button active only at expiry (otherwise disabled with a tooltip
  "Unlockable on …")
- Accrued rewards in BNB with ≈ $ value and a "Claim" button

## 7. Governance — with visible countdowns

**Proposal list** (read from ProposalCreated events + state from state()):
each card shows: id, description, proposer (truncated), current phase with a
countdown:

```
Pending        → "Voting opens in …"
Voting open    → Yes/No/Abstain bars with weights, "ends in …", vote buttons
                 (active only with voting power at the snapshot > 0)
Succeeded      → "Queue" button (queue)
In timelock    → 7-day countdown, then an "Execute" button (execute)
Executed/Defeated/Canceled → status badge
```

- Show the quorum: "Quorum: X / Y required (10%)" with a bar.
- The user's voting power shown at the top: the one AT THE SNAPSHOT of the
  selected proposal (votingPowerAt), not the live one — with a tooltip
  explaining why ("voting power is snapshotted at proposal creation to prevent
  manipulation").
- Proposal creation: an advanced form (target, value, calldata, description)
  behind an "Advanced mode" toggle — most will use it from multisig/external
  tools, but it must exist.
- The proposal #0 testnet queue → execute flow is the END-TO-END TEST of the
  dApp: it must work by July 21.

## 8. Cross-cutting rules (non-negotiable)

1. NO fake data: wallet not connected → an invitation to connect, not zeros.
2. Every transaction: visible state (waiting for signature → pending →
   confirmed/failed) with a link to the tx on BscScan.
3. Contract errors mapped to understandable messages in the UI language
   (LockStillActive, VotingClosed, ContractIsPaused, AmountMismatch,
   GuardianExpired, etc.). Never show raw revert strings. The mapping exists in
   both languages (§8.8).
4. If paused() is true: a global banner "The contract is temporarily paused
   for emergency" and actions disabled.
5. All amounts formatted readably (1.5M, 20B) with the exact value in a
   tooltip.
6. Responsive: mobile-first, the majority of BSC users are on mobile.
7. No third-party tracker/analytics. Consistent with the philosophy.
8. BILINGUAL interface English + Italian (updated 2026-07-22, previously
   Italian only). Rules:
   - Default ENGLISH; Italian on first visit only if it is the browser's
     primary language (Accept-Language). EN|IT selector in the header; the
     choice persists in a cookie (`daimon-locale`) and is read by the server
     too → the initial HTML and the first client render match (no hydration
     mismatch).
   - Implementation: lightweight custom dictionaries (src/messages/en.json +
     it.json, a React provider in LocaleProvider.tsx, lookup with
     interpolation in lib/i18n.ts). NO next-intl: 2 languages and no
     per-locale routing do not justify it.
   - The WHOLE UI is translated: pages, header/footer, banners, transaction
     notices, mapped errors, tooltips, metadata.
   - NOT translated: on-chain data (numbers, addresses, hashes, symbols),
     proposal descriptions (content written by the proposers).
   - Number formatting UNCHANGED between languages (floor-truncation
     included); dates and countdowns localized (it-IT ↔ en-US, "3g" ↔ "3d").

## 9. What NOT to include (explicit decisions)

- NO price charts (neither candles nor sparklines) — decided.
- NO 24h % change or red/green indicators on the price — decided.
- NO lending/borrowing section — it will arrive in phase 2, do not prepare UI.
- NO localStorage for sensitive data.
- NO integrated swap in the dApp — decided 2026-07-19: deferred to the phase-2
  DeFi, to be activated via a DAO proposal. Bridge solution: the "Buy DMN"
  button (§4) that opens PancakeSwap on the official pair.

## 10. Delivery

- Separate repo (daimon-dapp folder) or a subfolder of the monorepo, your
  reasoned choice.
- README with: local setup, environment variables, how to switch chain
  testnet→mainnet (a single config file), how to replace the logo.
- Final check: connection to the real BSC testnet, dashboard reading, and a
  full simulation of the voting flow on proposal #0.
