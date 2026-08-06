# Mainnet deploy checklist — Daimon DAO

To be executed **only after** the professional audit, on the scope frozen at
tag [`audit-scope-v2`](https://github.com/daimon-dao/daimon-dao/releases/tag/audit-scope-v2)
(English-commented contracts in `src/`, bytecode identical to `audit-scope-v1`).
Every line is blocking.

## Addresses (careful: some are IMMUTABLE)

- [ ] **`marketingWallet` → MULTISIG.** Never an EOA. Receives the marketing
      share of the fees. Modifiable only via governance/timelock, but it must
      be set correctly already at deploy (`initialize`).
- [ ] **Migration `treasury` → carefully chosen MULTISIG.** ⚠️ It is
      **`immutable`**: fixed in the `DaimonMigration` constructor and **cannot
      be changed** afterwards, not even via governance. Destination of the old
      tokens and of the post-deadline sweep. Getting it wrong is irreversible.
- [ ] **`guardian` → dedicated Ledger or multisig.** Defensive powers only
      (pause ≤36 months, cancel proposals). Must not coincide with the
      deployer.
- [ ] **`deployer` → dedicated Ledger.** Renounces all roles at the end of the
      script; use a hardware signer anyway, not a hot wallet.
- [ ] **`_governance` (Timelock) = the only GOVERNANCE_ROLE.** The deployer
      must end up with no roles after the wiring.

Note: on testnet marketing/treasury coincide with the deployer for testing
only — on mainnet they must be distinct multisigs.

## Automatic checks

- [ ] **`_assertDecentralized()` runs and passes on mainnet** (14 asserts in
      the deploy script): the timelock governs the token/staking, the deployer
      has no roles, no `DEFAULT_ADMIN`, the entire supply in the migration,
      etc.
- [ ] Contracts **verified on BscScan** (source + constructors).
- [ ] Timelock `MIN_DELAY` = **7 days**; `MIN_SUPPLY` = **21B**; fee cap 10%
      — confirmed on-chain post-deploy.

## Liquidity

**One pool only: DMN/WBNB on PancakeSwap V2**

- [ ] Create a single DMN/WBNB pair — this is the pair the fee-swap and
      buyback mechanisms operate on
- [ ] Do NOT create additional pools (DMN/USDT, DMN/BUSD or others). They
      would fragment liquidity, and the automated swap only operates on one
      pair. Routing through WBNB already lets anyone buy with any token.
- [ ] Verify the pair address stored in the contracts matches the pair
      actually created on mainnet — on testnet it was
      `0x9b44521E5643dD0E393C584E770598deC644a8B5`; a wrong address breaks
      fee-swap and buyback silently

**Decisions to make and document before launch**

- [ ] Initial liquidity amount — it determines slippage and how easily the
      price can be manipulated. Thin liquidity also makes the buyback
      mechanism behave poorly.
- [ ] What happens to the LP tokens: locked (verifiable, with a stated
      duration and platform), burned (permanent, irreversible), or held. For
      a project whose stated position is "don't trust, verify", a verifiable
      lock is the coherent choice — and the lock transaction should be
      published.
- [ ] Sequence relative to the migration window: opening trading before
      holders have migrated means the price forms on minimal volume. Decide
      and announce the order.

**After deployment**

- [ ] Verify a small test swap triggers the fee correctly (4%) and that
      accumulated fees reach the threshold path as expected
- [ ] Confirm the buyback path executes on a real pool with real slippage —
      this is the least-proven surface, flagged in the whitepaper and to
      every auditor

## dApp

- [ ] **`NEXT_PUBLIC_CHAIN_ID=56`** in the Vercel production env: automatically
      turns off `noindex` and the "test environment" banner, and makes the
      mainnet RPC/explorer/addresses cascade (fill in `BSC_MAINNET` in
      `daimon-dapp/src/config/contracts.ts`, including the PancakeSwap pair
      read from `daimonV2.uniswapV2Pair()`).
- [ ] Re-enable Deployment Protection if the URL must stay private on staging;
      for the public launch, official domain + WalletConnect allowlist.

## Domain and dApp distribution

**Primary — traditional domain + Vercel**

- [ ] Register a conventional domain (.io / .com / .xyz)
- [ ] Point it to the Vercel deployment
- [ ] Set `NEXT_PUBLIC_CHAIN_ID=56` (this alone removes the noindex tag and
      the testnet banner)
- [ ] Add the new domain to the WalletConnect/Reown allowlist
- [ ] Update every link: README, org profile, whitepaper, social channels
- [ ] Announce the official domain explicitly and repeatedly: at launch,
      clone sites will appear

**Mirror — decentralised, censorship-resistant**

- [ ] Register a blockchain domain (Unstoppable Domains: .crypto, .x)
- [ ] Export the dApp as a static site and publish it to IPFS
- [ ] Pin the content (Pinata, Web3.Storage or equivalent) — unpinned IPFS
      content becomes unavailable
- [ ] Point the blockchain domain to the IPFS hash
- [ ] Verify the static export does not break: the i18n cookie and the wagmi
      SSR state currently rely on server-side rendering, which a static
      export removes

**Why both**

The primary domain is fast, updates automatically and works in every browser.
The mirror cannot be seized or taken offline, and requires no hosting
provider. They are redundancy, not alternatives — the same reasoning that
keeps the contracts usable through a block explorer if the interface
disappears.

**Known limitation of the mirror**

Blockchain domains do not resolve in Chrome or Safari without an extension or
a gateway. A portion of users will not reach it directly. It is a fallback
and a statement of intent, not the main channel.

## Legal (before mainnet)

- [ ] Consult a crypto-specialised lawyer before mainnet deployment — not to
      incorporate, but to understand exposure, obligations and token
      classification under local and EU regulation (MiCA)
- [ ] Revisit the question of a legal structure once the protocol is live and
      the treasury can fund it. A structure decided by DAO vote and paid from
      protocol revenue is more coherent with the project than one funded
      personally in advance.
- [ ] Confirm the whitepaper disclaimer (Section 14) is adequate for the
      jurisdictions where the interface is accessible
- [ ] Review tax obligations arising from protocol operations and treasury
      holdings

Contracts requiring an identifiable counterparty — audits, listings, service
agreements — are signed by an individual member of the DAO. That is normal
for unincorporated projects, and the data stays with the counterparty. It
does not make the protocol any less ownerless: no signer holds any privileged
role on-chain.

## Post-launch governance

- [ ] `marketingWallet` and `stakingContract` remain modifiable **only** via
      proposal → vote → queue → timelock 7d → execute (no EOA path).
- [ ] Guardian renewal/rotation before the 36-month expiry, if desired, via
      governance.

---

**Freeze:** the contracts in `src/` are frozen at tag `audit-scope-v2`. Any
change to the contracts before mainnet requires a new tag (`audit-scope-v3`,
…) and re-running the checks.
