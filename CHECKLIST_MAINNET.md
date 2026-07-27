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

- [ ] **`_assertDecentralized()` runs and passes on mainnet** (13 asserts in
      the deploy script): the timelock governs the token/staking, the deployer
      has no roles, no `DEFAULT_ADMIN`, the entire supply in the migration,
      etc.
- [ ] Contracts **verified on BscScan** (source + constructors).
- [ ] Timelock `MIN_DELAY` = **7 days**; `MIN_SUPPLY` = **21B**; fee cap 10%
      — confirmed on-chain post-deploy.

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

## Post-launch governance

- [ ] `marketingWallet` and `stakingContract` remain modifiable **only** via
      proposal → vote → queue → timelock 7d → execute (no EOA path).
- [ ] Guardian renewal/rotation before the 36-month expiry, if desired, via
      governance.

---

**Freeze:** the contracts in `src/` are frozen at tag `audit-scope-v2`. Any
change to the contracts before mainnet requires a new tag (`audit-scope-v3`,
…) and re-running the checks.
