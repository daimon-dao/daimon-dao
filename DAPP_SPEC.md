# DAPP_SPEC.md — Daimon (DMN) dApp specification

Complete specification for building the dApp. To be read together with the
contracts repository and TESTNET_RESULTS.md for the testnet addresses.

Status: the dApp is built and live on BNB Smart Chain mainnet at
https://app.daimon.money since the 2026-09-29 launch; both address sets
(testnet 97, mainnet 56) are in `daimon-dapp/src/config/contracts.ts`, and
the launch is recorded in
[docs/MAINNET_LAUNCH_RECORD.md](docs/MAINNET_LAUNCH_RECORD.md). This
document is kept as the original build specification.

---

## 1. Technical stack

```
Framework:         Next.js 15 (App Router, React 19) + TypeScript
Styling:           TailwindCSS
Wallet/chain:      wagmi v2 + viem (NO web3.js, NO ethers)
Supported wallets: MetaMask, WalletConnect, Trust Wallet (via wagmi connectors)
Chain:             BSC mainnet (56) live since 2026-09-29, BSC testnet (97)
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
4. DMN price (pool price only, no market cap: removed 2026-09-29, the
   figure counted the ~995B DMN still held by the Migration) — SOBER NUMBER:
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
  "If and when the floor is reached, 100% of the revenue will go to stakers"
  (conditional on purpose: the floor is a bound, not a guaranteed
  destination — tokens in lost wallets can keep the burn permanently above
  it; see protocol paper 6.2)

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

- **The phase comes from `Governor.state(id)`, never from the `canceled`
  flag of `proposals(id)`.** After a direct Timelock cancel
  (`Timelock.cancel(opId)`, the guardian stopping a queued operation without
  the Governor) the struct's flag stays `false` while `state(id)` reads the
  Timelock and returns Canceled (observed on Chapel, campaign 2b, H4.7). A
  card built from the flag would show a dead proposal "In timelock" with an
  "Execute" button that can only revert.

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
   - Number formatting PER LANGUAGE (decision 2026-09-30, replacing
     "unchanged between languages"): EN "," thousands, "." decimals, M/B
     ("1,000B DMN"); IT "." thousands, "," decimals, mln/mld ("1.000 mld di
     DMN"). No thousands suffix: below a million amounts are written in full
     ("1.000 DMN", "250.000 DMN" / "1,000 DMN"). An amount never breaks
     across lines (no-break spaces). One formatter (daimon-dapp/src/lib/format.ts) for headline
     figures and tooltips alike; floor-truncation kept. Dates and countdowns
     localized (it-IT ↔ en-US, "3g" ↔ "3d").
9. First-visit acknowledgment: the dApp must show the full legal terms on
   first interaction and require explicit acceptance before enabling any
   contract interaction.
10. Jurisdiction restriction — DECISION 2026-09-29: the frontend does NOT
    restrict access by location (DISCLAIMER_TERMS v0.3 §5: each user is
    responsible for lawful use where they are). The edge mechanism exists
    but is dormant: RESTRICTED_COUNTRIES in daimon-dapp/src/config/
    restricted.ts is empty; filling it switches the restriction on, and
    requires amending §5 in the same release. The smart contracts remain
    permissionless either way.

### 8.x Liquidity operations: disclose the real cost (Zenith #16, #17)

The token charges a transfer fee, and liquidity operations cross the token
twice. The contracts accept this; the **interface must not let a user discover
it after signing**.

- **Removing liquidity pays the fee TWICE**: once on pair → router, once on
  router → user. The interface must state that two fees apply and show the
  amount the user will actually receive, not the router's gross figure.
- **Adding liquidity yields fewer LP tokens than the router quotes**: the
  router computes on the gross amount while the pair receives the net. The
  interface must present the effective figure, and must not repeat the
  router's estimate as if it were the outcome.
- Wherever an amount is shown before signing, it is the **net the user gets**,
  with the fee stated separately — the same rule already applied to transfers
  in §8.5.

⚠️ **Never propose exempting the pair or the router as a workaround.** It
would disable fees on every buy and sell, and would open a fee-free transfer
route: pre-deposit tokens, then call liquidity removal to take them out
untaxed. The double fee is by far the lesser cost. See
[THREAT_MODEL.md §7](THREAT_MODEL.md).

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
