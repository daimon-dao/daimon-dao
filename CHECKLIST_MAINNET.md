# Mainnet deploy checklist â€” Daimon DAO

To be executed **only after** the professional audit, on the scope frozen at
tag [`audit-scope-v2`](https://github.com/daimon-dao/daimon-dao/releases/tag/audit-scope-v2)
(English-commented contracts in `src/`, bytecode identical to `audit-scope-v1`).
Every line is blocking.

## âš ï¸ Predecessor token configuration (Zenith #29)

BLOCKING: migration cannot work without this, and the deadline is immutable
once Migration is deployed.

The Migration contract is only the allowance spender. The actual old token
transfer is claimant â†’ treasury. DMX disables fees only when `from` or `to`
is exempt, so exempting Migration has no effect.

- [ ] Call `oldDaimon.excludeFromFee(TREASURY_ADDRESS)` â€” the treasury, NOT
      the Migration contract
- [ ] Verify on-chain that the exemption is active
- [ ] Confirm the DMX owner still has authority to set exemptions (ownership
      was never renounced â€” verify it is still the case)
- [ ] Simulate a transfer from a non-exempt holder to treasury and confirm
      exact receipt, no fee deducted
- [ ] Only after all of the above: deploy Migration.
      Do NOT start the immutable deadline before this is confirmed

Correct the misleading comment in `DaimonMigration.sol` that instructs
exempting the Migration contract.

**Legacy token custody (Zenith #6)**

`claim()` sends the collected old tokens to the treasury rather than burning
or locking them. That is accepted as a custody risk, not a code property â€” so
it becomes an operational requirement:

- [ ] The collected legacy tokens remain in **non-circulating custody for the
      entire migration window**. They must not be sold, lent, bridged or moved
      to any address that could return them to a holder: tokens back in
      circulation before the deadline can be migrated a second time.
- [ ] Decide and record who holds that custody and under what controls, before
      the migration opens â€” the window is armed by an immutable deadline and
      cannot be paused to fix this later.

## Addresses (careful: some are IMMUTABLE)

- [ ] **`marketingWallet` â†’ MULTISIG.** Never an EOA. Receives the marketing
      share of the fees. Modifiable only via governance/timelock, but it must
      be set correctly already at deploy (`initialize`).
- [ ] **Migration `treasury` â†’ carefully chosen MULTISIG.** âš ï¸ It is
      **`immutable`**: fixed in the `DaimonMigration` constructor and **cannot
      be changed** afterwards, not even via governance. Destination of the old
      tokens and of the post-deadline sweep. Getting it wrong is irreversible.
- [ ] **`guardian` â†’ dedicated Ledger or multisig.** Defensive powers only
      (pause â‰¤36 months, cancel proposals). Must not coincide with the
      deployer.
- [ ] **`deployer` â†’ dedicated Ledger.** Renounces all roles at the end of the
      script; use a hardware signer anyway, not a hot wallet.
- [ ] **`_governance` (Timelock) = the only GOVERNANCE_ROLE.** The deployer
      must end up with no roles after the wiring.

Note: on testnet marketing/treasury coincide with the deployer for testing
only â€” on mainnet they must be distinct multisigs.

## Automatic checks -- two-phase deploy + post-broadcast verification

The deploy is TWO separate broadcasts. The reason (Level 1 campaign,
deviation A1.8): a single-broadcast script fixes the guardian expiry it
passes to the Timelock/Governor constructors during SIMULATION, while the
token computes its own from the block it is MINED in -- on a live chain the
values skew by the simulation-to-inclusion delay, and no in-script assert
can see it. Phase 2 reads the mined value from the live chain instead.

- [ ] **Phase 1 -- `DeployPhase1.s.sol`** (Migration + token; 10 asserts):
      supply entirely in the migration, migration fee-exempt, marketing
      wallet as configured, guardian role live, migration wiring (all
      immutable), and `migration.governance` bound to the PREDICTED timelock
      address. Writes `deployments/two-phase-<chainid>.json` -- addresses and
      expected nonce only, deliberately NO expiry value.
- [ ] **Between the phases: send NOTHING from the deployer.** A nonce change
      makes the predicted timelock address unreachable and phase 2 will
      refuse. If phase 2 refuses for any reason, do NOT work around it:
      abandon the phase-1 contracts and rerun phase 1 fresh (nothing public
      has happened yet; the only cost is gas).
- [ ] **Phase 2 -- `DeployPhase2.s.sol`** (Timelock + Staking + Governor +
      wiring + renounce; 19 asserts): preflight refuses to broadcast unless
      the live chain matches the state file (nonce, code, linkage, supply);
      the guardian expiry is read from the LIVE token and passed verbatim --
      no file and no human ever carries it; the timelock MUST land on the
      address phase 1 predicted; `stakingRewardShareBps == 1000`
      (legal-compliance launch configuration) set and asserted here. If
      phase 2 is interrupted mid-broadcast, resume with `--resume` -- a
      fresh rerun would shift nonces and refuse.
- [ ] **Post-broadcast verification -- `script/verify-deploy.ps1 -Rpc <url>`
      passes with exit code 0 (33 checks). MANDATORY LAUNCH GATE.** The
      in-script asserts above run in the simulation context; this runner
      re-reads every invariant from MINED state through plain `eth_call`:
      roles, admin absence, supply placement, canceller roles, launch share
      at 1000, migration wiring, and the guardian expiry EXACTLY equal
      across the three contracts -- no tolerance window, since the
      two-phase design removes the reason for one. Paste its full output
      into the launch record.
- [ ] Contracts **verified on BscScan** (source + constructors).
- [ ] Timelock `MIN_DELAY` = **7 days**; `MIN_SUPPLY` = **21B**; fee cap 10%;
      `MAX_PAUSE_DURATION` = **14 days** -- confirmed on-chain post-deploy
      (the expiry parity line is covered by the verification above).

## Liquidity

**Before deployment (Zenith #25)**

- [ ] Check whether a DMN/WBNB pair already exists on the target factory.
      `initialize()` calls `createPair()` unconditionally and reverts if one
      exists â€” an observer can predict the proxy address and pre-create the
      pair to block the deploy
- [ ] The fix (using `getPair()` first) must be in the deployed
      implementation
- [ ] Consider private transaction submission as defence in depth

**Initial liquidity pricing (Zenith #17)**

The pair is not fee-exempt, so it receives the NET amount while the router
calculates from the gross. Computing the BNB contribution from the gross DMN
input initializes the pool at the wrong price.

- [ ] Calculate the BNB contribution from the DMN the pair ACTUALLY
      receives, not from the amount sent
- [ ] Verify the resulting reserve ratio matches the intended opening price
      before proceeding
- [ ] Do NOT blanket-exempt the pair or the router as a workaround â€” it
      would disable fees on all buys and sells, and enable fee-free
      transfers through liquidity removal

**Automation state at launch (Zenith #27)**

- [ ] Automation (fee swap and buyback) must be DISABLED or the fail-open
      fix deployed before the pair has reserves. An attacker can donate
      ~1 BNB to the token contract before initial liquidity and block the
      launch
- [ ] Verify both reserves are non-zero and all recipients functional before
      enabling automation

**One pool only: DMN/WBNB on PancakeSwap V2**

- [ ] Create a single DMN/WBNB pair â€” this is the pair the fee-swap and
      buyback mechanisms operate on
- [ ] Do NOT create additional pools (DMN/USDT, DMN/BUSD or others). They
      would fragment liquidity, and the automated swap only operates on one
      pair. Routing through WBNB already lets anyone buy with any token.
- [ ] Verify the pair address stored in the contracts matches the pair
      actually created on mainnet â€” on testnet it was
      `0x9b44521E5643dD0E393C584E770598deC644a8B5`; a wrong address breaks
      fee-swap and buyback silently

**Decisions to make and document before launch**

- [ ] Initial liquidity amount â€” it determines slippage and how easily the
      price can be manipulated. Thin liquidity also makes the buyback
      mechanism behave poorly.
- [ ] What happens to the LP tokens: locked (verifiable, with a stated
      duration and platform), burned (permanent, irreversible), or held. For
      a project whose stated position is "don't trust, verify", a verifiable
      lock is the coherent choice â€” and the lock transaction should be
      published.
- [ ] Sequence relative to the migration window: opening trading before
      holders have migrated means the price forms on minimal volume. Decide
      and announce the order.

**After deployment**

- [ ] Verify a small test swap triggers the fee correctly (4%) and that
      accumulated fees reach the threshold path as expected
- [ ] Confirm the buyback path executes on a real pool with real slippage â€”
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

## Fee automation (post-fix Zenith #1)

- [ ] **Monitor the token contract's DMN balance** after launch:
      `balanceOf(DaimonV2)` is the fee inventory not yet converted.
- [ ] Once it exceeds `minimumTokensBeforeSwap`, a **1-wei DMN transfer to
      the pair**, from any address, triggers the conversion (at most one
      fee-swap chunk and one buyback slice per block: #28 budgets). The
      buyback BNB moves the same way â€” and only this way: sales through the
      router no longer trigger anything.
- [ ] **NOT a security requirement**: if the poke stops, fees simply
      accumulate â€” no deadline, no loss; conversion resumes with the next
      poke. Full model and rationale in THREAT_MODEL.md Â§8
      (âš ï¸ do not "fix" this by reintroducing the sell trigger: it would
      reopen finding #1).

## Post-launch governance

- [ ] `marketingWallet` and `stakingContract` stay modifiable **only** via
      proposal â†’ vote â†’ queue â†’ 7-day timelock â†’ execute (no EOA path).
- [ ] Guardian renewal/rotation before the 36-month expiry, if desired, via
      governance.

## Domain and dApp distribution

**Primary â€” traditional domain + Vercel**

- [ ] Register a conventional domain (.io / .com / .xyz)
- [ ] Point it to the Vercel deployment
- [ ] Set `NEXT_PUBLIC_CHAIN_ID=56` (this alone removes the noindex tag and
      the testnet banner)
- [ ] Add the new domain to the WalletConnect/Reown allowlist
- [ ] Update every link: README, org profile, whitepaper, social channels
- [ ] Announce the official domain explicitly and repeatedly: at launch,
      clone sites will appear

**Mirror â€” decentralised, censorship-resistant**

- [ ] Register a blockchain domain (Unstoppable Domains: .crypto, .x)
- [ ] Export the dApp as a static site and publish it to IPFS
- [ ] Pin the content (Pinata, Web3.Storage or equivalent) â€” unpinned IPFS
      content becomes unavailable
- [ ] Point the blockchain domain to the IPFS hash
- [ ] Verify the static export does not break: the i18n cookie and the wagmi
      SSR state currently rely on server-side rendering, which a static
      export removes

**Why both**

The primary domain is fast, updates automatically and works in every browser.
The mirror cannot be seized or taken offline, and requires no hosting
provider. They are redundancy, not alternatives â€” the same reasoning that
keeps the contracts usable through a block explorer if the interface
disappears.

**Known limitation of the mirror**

Blockchain domains do not resolve in Chrome or Safari without an extension or
a gateway. A portion of users will not reach it directly. It is a fallback
and a statement of intent, not the main channel.

## Legal (before mainnet)

- [ ] Consult a crypto-specialised lawyer before mainnet deployment â€” not to
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

Contracts requiring an identifiable counterparty â€” audits, listings, service
agreements â€” are signed by an individual member of the DAO. That is normal
for unincorporated projects, and the data stays with the counterparty. It
does not make the protocol any less ownerless: no signer holds any privileged
role on-chain.

## Post-launch governance

- [ ] `marketingWallet` and `stakingContract` remain modifiable **only** via
      proposal â†’ vote â†’ queue â†’ timelock 7d â†’ execute (no EOA path).
- [ ] Guardian renewal/rotation before the 36-month expiry, if desired, via
      governance.

---

**Freeze:** the contracts in `src/` are frozen at tag `audit-scope-v2`. Any
change to the contracts before mainnet requires a new tag (`audit-scope-v3`,
â€¦) and re-running the checks.

## Contract upgradeability â€” read before planning any fix

DaimonV2 is behind a UUPS proxy and can be upgraded by governance.
DaimonGovernor, DaimonTimelock and DaimonStaking are NOT upgradeable.

Any correction to the non-upgradeable contracts must be deployed before
mainnet. Afterwards it would require redeploying them and rewiring every
role and immutable reference â€” DaimonGovernor stores the Staking address
immutably.
