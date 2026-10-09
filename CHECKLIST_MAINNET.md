# Mainnet deploy checklist — Daimon DAO

**Launch completed 2026-09-29 — see the [launch record][rec].**

This checklist is closed and kept as the historical record of what the
launch had to satisfy. It was executed through
[docs/LAUNCH_DAY.md](docs/LAUNCH_DAY.md). Every ticked item points to the
section of [docs/MAINNET_LAUNCH_RECORD.md][rec] where it was done and read
back from mined state. **SKIPPED** marks a launch step that was not run,
with the reason. **In force** marks a duty that runs past the launch.
**OPEN** marks an item the launch did not close. **ON HOLD** marks an
item paused by decision, with the date and the reason.

To be executed **only after** the professional audit, on the range frozen at
tag [`audit-final`](https://github.com/daimon-dao/daimon-dao/releases/tag/audit-final)
(the audited code: the scope submitted at `audit-scope-v2` plus the 29 fixes;
`git diff audit-final -- src/` must be empty; `forge test` passes 203
tests: the 180 of `audit-final`, the 7 of `test/OldDaimonMaxTx.t.sol` and
the 16 of `test/LiquiditySeeder.t.sol`).
The launch configuration below was rehearsed end to end on Chapel
(docs/CHAPEL_2B_RESULTS.md, tag `launch-config-rc1`) and then on a local
fork of BSC mainnet against the REAL DMX, DMX pool and PancakeSwap router
(docs/MAINNET_FORK_RESULTS.md, branch `rehearsal/mainnet-fork`). The
launch-day script, command by command: docs/LAUNCH_DAY.md.
Every line was blocking.

## Predecessor token configuration (Zenith #29) -- and WHEN it happens

The Migration contract is only the allowance spender. The actual old-token
transfer is claimant -> treasury. DMX disables fees only when `from` or `to`
is exempt, so exempting Migration has no effect: the exemption target is the
TREASURY -- which, since the two-phase deploy, IS the Timelock.

**The predecessor, recorded here explicitly** (until now it appeared only in
the protocol paper, section 4.1):

- DMX token: `0x36EbA94407B53c631eE822C219e94580fadd67c7` (BSC mainnet,
  chain 56).
- DMX owner: `0xF8EC459CAEaF1052b64B38BDD67290B0c132B0Ae` -- an EOA,
  ownership never renounced. Verified 2026-09-10 at block 121108614;
  re-read on 2026-09-11 at block 121166526 (`owner()` returns that address,
  which holds no code).
- DMX `_maxTxAmount` = 1.5B (1500000000 * 1e18, read 2026-09-11). It applies
  to `claim()` too -- see launch order step 11a below.
- The two DMX marketing wallets: `marketingAddress1` = the owner above,
  `marketingAddress2` = `0x41B533AF0Db427dc97988B47f86383f42372f395`.
  Decision: the project wallets claim ONLY the initial-liquidity quota --
  the DMX owner, at launch step 5a, before the migration window opens --
  with the LP tokens minted directly to the Timelock by the
  LiquiditySeeder in the same transaction (step 5b, which absorbs step 6).
  Everything else stays in the Migration contract, reaches the
  treasury through `sweepUnclaimed()` after the deadline, and does not vote
  (docs/TREASURY_POLICY_v1.0.md, sections 2 and 6b).

The exemption is what makes claims possible: without it, `claim()` reverts
with `AmountMismatch` (#29 -- by design, and proven on-chain by campaign
scenario A0). So it is performed LAST, after both deploy phases AND the
post-broadcast verification are green: no claim can occur against a
deployment that has not been verified, and between the phases the migration
is inert by construction.

BEFORE phase 1 (de-risking the immutable deadline, which starts at phase 1):

- [x] Confirm the DMX owner still has authority to set fee exemptions
      (ownership was never renounced -- verify it is still the case). If it
      cannot, the migration can never open: do NOT deploy anything.
      Done -- record: [Preflight][r-pre], P5 (`owner()` = the owner,
      `getUnlockTime` 0, the owner fee-exempt).
- [x] Rehearse on a fork: exempt a test recipient, simulate a transfer from
      a non-exempt holder to it, confirm exact receipt with no fee deducted.
      DONE on the mainnet fork against the REAL DMX: after 11b a real
      holder claimed 10.00 B and another 1.00 B, exact on every leg
      (docs/MAINNET_FORK_RESULTS.md, F12.1/F12.2). On mainnet after 11b,
      claims of 2e27 and 1e27 simulated from a real holder succeed --
      record: [After 11b][r-post11].
- [x] **The DMX owner must NEVER call `lock()` on DMX** (nor
      `renounceOwnership` / `transferOwnership`) from now until 11b is
      done. The real DMX is a SafeMoon-style `Ownable`: `lock(time)` zeroes
      `owner()` until `unlock()` after the lock time, and during a lock
      nobody can call `excludeFromFee` or `setMaxTxAmount` -- the migration
      could not open while its immutable deadline runs. `getUnlockTime()`
      must read 0 on the morning (docs/LAUNCH_DAY.md, P5).
      Held through 11b: `getUnlockTime()` 0 at [Preflight][r-pre] P5,
      [Step 8][r-8], [Before 11a][r-pre11] and [After 11b][r-post11].
      **In force** for the WHOLE migration window, until 2026-12-28
      01:08:44 UTC, with two more calls forbidden (`includeInFee(TL)`, a
      `setMaxTxAmount` below 1e30) -- record: [The owner-key rule][r-rule].

AFTER the post-broadcast verification -- launch order step 11, the LAST
step, split in TWO owner calls on the predecessor, in ONE session, in this
order:

- [x] **11a -- `setMaxTxAmount` raised on DMX.** DMX's 1.5B `_maxTxAmount`
      applies to `claim()` too: the claim is a DMX transfer claimant ->
      treasury, and the fee exemption does NOT lift the transfer cap. Large
      claims (the 76.9B top holder, any holder above 1.5B) would revert.
      Raise it FIRST, to the full supply (1000B, `1000000000000 * 1e18`),
      as rehearsed on Chapel; verify the new value on-chain.
      Done 2026-09-29 18:53:34 UTC; `_maxTxAmount()` == 1e30 read back --
      record: [Step 11a, then 11b][r-11].
- [x] **11b -- `oldDaimon.excludeFromFee(<TIMELOCK>)`** -- the treasury (=
      the Timelock deployed in phase 2), NOT the Migration contract. This
      is the call that opens the migration window, so it goes LAST: after
      11a, in the same session, nothing between them.
      Done 2026-09-29 20:06:24 UTC, block 124777699 -- record:
      [Step 11a, then 11b][r-11].
- [x] Neither call emits an event on the real DMX (the mock did): record
      both transaction hashes by hand; nothing that watches logs sees them.
      Done: both hashes, 0 logs each -- record: [Step 11a, then 11b][r-11].
- [x] Verify on-chain that the exemption is active.
      Done: `isExcludedFromFee(TL)` true -- record: [After 11b][r-post11].
- [x] Simulate one claim end-to-end and confirm exact 1:1 receipt.
      Done by `eth_call` from a real holder: 2e27 (above the old cap) and
      1e27 both succeed, so the Migration's own 1:1 check passes -- record:
      [After 11b][r-post11].
- [x] The migration window effectively OPENS at 11b. The immutable deadline
      started at phase 1, claims open at this step: a difference of minutes
      against a window of months, accepted deliberately.
      In the event the difference was about 19 hours, not minutes: the
      deadline started at 01:08:44 UTC and the window opened at 20:06:24
      UTC, because the launch paused after 5b -- record: [Step 2][r-2],
      [Status][r-status].

Launch order, numbered (docs/SCENARI_TESTNET.md G6, with the predecessor
exemption moved from first to last -- TWO_PHASE_RESULTS.md -- and the LP
step added):

```
 1  pair DMN/WBNB does NOT already exist on the factory (#25)
 2  phase 1 + phase 2 deploy, stakingRewardShareBps = 1000
 3  post-broadcast verification, 36/36 (MANDATORY GATE)
 4  automation inert until the pair has reserves (#27, fail-open fix)
 5a the DMX owner (fee- and maxTx-exempt on DMX) claims ONLY the DMN
    needed for the initial liquidity, before the window opens
 5b initial liquidity THROUGH THE LiquiditySeeder (script/launch/): the
    largest single add under the DMN 5B maxTx cap (~4.8B net), priced
    at the DMX pool price read live that day, DMN sent gross for the 4%
    (#17); one owner call wraps the BNB, sends both legs and mints the
    LP DIRECTLY to the Timelock; price checked on-chain within 0.10 %
 6  merged into 5b: assert, from the seed transaction and from state,
    Timelock LP == totalSupply - 1000, owner LP == 0, deployer LP == 0
 7  one pool only; stored pair == factory pair
 8  reserves non-zero -> automation live
 9  small test swap -> fee applied
10  first poke -> converts NOTHING on launch day (fee inventory ~0.15B
    from the 5b transfer, below the 0.2B threshold); zero BNB to the
    Timelock. The first conversion comes later, with volume
11a DMX setMaxTxAmount raised to the full supply (owner call, same
    session as 11b)
11b DMX excludeFromFee(TIMELOCK) -- the migration window opens here
```

How each step went on 2026-09-29:

| step | outcome | record |
|---|---|---|
| 1 | done: `getPair` = `0x0` | [Step 1][r-1] |
| 2 | done: phase 1 at nonces 0-2, phase 2 at nonces 3-18, all status 1 | [Step 2][r-2] |
| 3 | done: **36/36**, exit 0 | [Step 3][r-3] |
| 4 | done: reserves 0/0, token BNB 0, no donation; seeder deployed (4b), sources verified (4c) | [Step 4][r-4], [4b][r-4b], [4c][r-4c] |
| 5a | done: the owner claimed GROSS, 4999548574361503910682398180 | [Step 5a][r-5a] |
| 5b | done: 1.994 BNB and NET DMN; opening price 0.0024 ppm from the DMX price | [Step 5b][r-5b] |
| 6 | done inside 5b: Timelock LP == totalSupply - 1000; owner and deployer LP 0 | [Step 5b][r-5b] |
| 7 | done: one pool; factory pair == the pair `initialize` created | [Step 7][r-7] |
| 8 | done, re-baselined after the incident | [Step 8][r-8] |
| 9 | **SKIPPED** (decision): the 4 % fee was verified to the wei on the MEV bot's real buy and sell, tx `0xa1238092...d048` | [Step 9][r-9], [Incident][r-inc] |
| 10 | **SKIPPED** (decision): the MEV bot's real transaction had already made the first poke and the first conversion; after it the inventory (51,554 DMN) was far below the 0.2 B threshold, so a poke would convert nothing | [Step 10][r-10], [Incident][r-inc] |
| 11a | done: `_maxTxAmount` 1e30 | [Step 11a, then 11b][r-11] |
| 11b | done: **the migration window opened 2026-09-29 20:06:24 UTC** | [Step 11a, then 11b][r-11] |

The deployer and the DMX owner are two different wallets. The deployer
signs phases 1 and 2 and nothing between them; the DMX owner signs 5a,
5b (deploys the seeder, approves exactly, seeds), 9, 10, 11a and 11b (9 and
10 were skipped). Only the DMX owner can claim before 11b: it is
exempt from DMX's fee and cap, so its claim is exact 1:1 while the
treasury is not yet exempt (Chapel 2b, H1.10-H1.14). Why 5b is sized by
the cap and not by a BNB amount: a non-exempt provider's single add is
bound by DMN's own 5B `maxTxAmount`, and a second router add would
re-price on the gross (#17). Decision (c): no parameter change, no
exemption to any person; further depth comes from the treasury by
proposal (GOVERNANCE_ROLE is maxTx-exempt).

**Legacy token custody (Zenith #6)**

`claim()` sends the collected old tokens to the treasury rather than burning
or locking them. That is accepted as a custody risk, not a code property — so
it becomes an operational requirement:

- [x] The collected legacy tokens remain in **non-circulating custody for the
      entire migration window**. They must not be sold, lent, bridged or moved
      to any address that could return them to a holder: tokens back in
      circulation before the deadline can be migrated a second time.
      **In force** until `sweepUnclaimed()` has executed: the DMX sit in the
      Timelock, `DMX.balanceOf(TL) >= totalMigrated` -- record:
      [After 11b][r-post11].
- [x] Decide and record who holds that custody and under what controls, before
      the migration opens — the window is armed by an immutable deadline and
      cannot be paused to fix this later.
      Decided: the Timelock, the Migration's immutable `treasury`; nothing
      leaves it without proposal -> vote -> 7-day delay, and the guardian
      Safe can cancel (docs/TREASURY_POLICY_v1.0.md, section 2). In place
      before the window opened -- record: [Step 3][r-3]
      (`migration: treasury is the timelock`).

## Addresses (careful: some are IMMUTABLE)

- [x] **`marketingWallet` -> the predicted Timelock address** (the same
      prediction as the Migration `treasury`), share 1000 at launch; NOT a
      multisig, NOT an EOA. Receives the marketing share of the fees --
      nothing, while `stakingRewardShareBps == 1000`. Set at deploy
      (`initialize`, phase 1) before the Timelock exists: phase 2 must land
      the Timelock on that address. Modifiable afterwards only via
      governance/timelock.
      Done -- record: [Step 2][r-2] (2.1: treasury and marketing = the
      predicted Timelock), [Step 3][r-3].
- [x] **Migration `treasury` = the Timelock, DERIVED -- there is nothing to
      set.** It is **`immutable`** (fixed in the `DaimonMigration`
      constructor, unchangeable even by governance) and receives the old
      tokens and the post-deadline sweep. Since the two-phase deploy it is
      NOT an input: phase 1 binds it to the same predicted timelock address
      as the migration's governance, phase 2 verifies the prediction came
      true, and the post-broadcast verification re-checks it from live
      state. `TREASURY_ADDRESS` no longer exists; rehearsals may use
      `TESTNET_TREASURY_OVERRIDE` (loudly logged, refused on chain 56).
      Done -- record: [Step 3][r-3].
- [x] **`guardian` -> the 2-of-3 Safe
      `0x37F45839765AD3418E29c97d5D92407Ddbf5c7a8`**, held by three
      different people (hardware wallets). Defensive powers only (pause and
      cancel, for a 36-month mandate). Must not coincide with the deployer.
      Done -- record: [Preflight][r-pre] (the Safe on chain: threshold 2,
      three owners), [Step 2][r-2] (the guardian in the `initialize`
      calldata), [Step 3][r-3].
- [x] **`deployer` → dedicated Ledger.** Renounces all roles at the end of the
      script; use a hardware signer anyway, not a hot wallet.
      Done -- record: [Preflight][r-pre] P3, [Step 2][r-2] (signed on the
      Ledger), [Step 3][r-3] (no roles left).
- [x] **The deployer is NOT the DMX owner.** Two different wallets: the
      deployer signs the two deploy phases only; the DMX owner signs the
      liquidity claim (5a), the liquidity (5b), the LP transfer (6) and the
      two predecessor calls (11a, 11b).
      Done: deployer `0x4D38...a26e`, DMX owner `0xF8EC...B0Ae` -- record:
      [Preflight][r-pre] P3, [Step 5a][r-5a].
- [x] **`_governance` (Timelock) = the only GOVERNANCE_ROLE.** The deployer
      must end up with no roles after the wiring.
      Done -- record: [Step 3][r-3].

Note: the testnet rehearsals used a sentinel marketing wallet (`0x...A001`,
watched because it must receive nothing) -- on mainnet it is the predicted
Timelock, exactly like the treasury. The treasury is derived on every chain.

## Automatic checks -- two-phase deploy + post-broadcast verification

The deploy is TWO separate broadcasts. The reason (Level 1 campaign,
deviation A1.8): a single-broadcast script fixes the guardian expiry it
passes to the Timelock/Governor constructors during SIMULATION, while the
token computes its own from the block it is MINED in -- on a live chain the
values skew by the simulation-to-inclusion delay, and no in-script assert
can see it. Phase 2 reads the mined value from the live chain instead.

- [x] **Phase 1 -- `DeployPhase1.s.sol`** (Migration + token; 10 asserts):
      supply entirely in the migration, migration fee-exempt, marketing
      wallet as configured, guardian role live, migration wiring (all
      immutable), and `migration.governance` AND `migration.treasury` both
      bound to the PREDICTED timelock address -- the treasury is DERIVED,
      there is no treasury input. Writes `deployments/two-phase-<chainid>.json`
      -- addresses and expected nonce only, deliberately NO expiry value.
      Done (2.2) -- record: [Step 2][r-2].
- [x] **Between the phases: send NOTHING from the deployer.** A nonce change
      makes the predicted timelock address unreachable and phase 2 will
      refuse. If phase 2 refuses for any reason, do NOT work around it:
      abandon the phase-1 contracts and rerun phase 1 fresh. Nothing public
      has happened yet -- in particular the predecessor fee exemption is not
      in place, so NO CLAIM can have occurred: the only cost is gas.
      Held: phase 1 at nonces 0-2, phase 2 from nonce 3, the Timelock on the
      predicted address -- record: [Step 2][r-2].
- [x] **Phase 2 -- `DeployPhase2.s.sol`** (Timelock + Staking + Governor +
      wiring + `setFees(10, 10, 20)` by the deployer's temporary
      GOVERNANCE_ROLE before the hand-over + renounce; 25 asserts):
      preflight refuses to broadcast unless
      the live chain matches the state file (nonce, code, linkage, supply);
      the guardian expiry is read from the LIVE token and passed verbatim --
      no file and no human ever carries it; the timelock MUST land on the
      address phase 1 predicted (fulfilling BOTH predictions: governance and
      treasury); `stakingRewardShareBps == 1000`
      (legal-compliance launch configuration) set and asserted here. If
      phase 2 is interrupted mid-broadcast, resume with `--resume` -- a
      fresh rerun would shift nonces and refuse.
      Done (2.3: 16 transactions, `All decentralization asserts passed`) --
      record: [Step 2][r-2].
- [x] **Post-broadcast verification -- `script/verify-deploy.ps1 -Rpc <url>`
      passes with exit code 0 (36 checks). MANDATORY LAUNCH GATE.** The
      in-script asserts above run in the simulation context; this runner
      re-reads every invariant from MINED state through plain `eth_call`:
      roles, admin absence, supply placement, canceller roles, launch share
      at 1000, migration wiring including treasury == the Timelock read
      live, and the guardian expiry EXACTLY equal
      across the three contracts -- no tolerance window, since the
      two-phase design removes the reason for one. Paste its full output
      into the launch record.
      The two checks added with the phase-2 `setFees` call are EFFECTIVE in
      the script: `fees == (10, 10, 20)` and `marketingWallet == the
      deployed Timelock`, re-read from mined state (34 -> 36). 36/36 green
      on Chapel from mined state (docs/CHAPEL_2B_RESULTS.md, H1.7).
      Done: **36/36**, exit 0; full output in
      `docs/launch-56/step3-verify-deploy-56.txt` -- record: [Step 3][r-3].
- [x] **ONLY THEN, launch order step 11: DMX `setMaxTxAmount` raised (11a),
      then the predecessor fee exemption (11b)** -- see the #29 section
      above. The migration window opens at 11b, against a deployment that
      has already passed every gate.
      Done -- record: [Before 11a][r-pre11], [Step 11a, then 11b][r-11].
- [x] **`MIGRATION_DURATION` = 7776000 (90 days)**, set explicitly in the
      phase-1 environment (unset, the script defaults to 30 days). The
      deadline is immutable from the Migration's deploy block: read back
      `migrationDeadline()` == that block's timestamp + 7776000 (rehearsed
      on the mainnet fork, F2.2b).
      Done: 1790644124 + 7776000 = 1798420124 == `migrationDeadline()` --
      record: [Session][r-session], [Step 2][r-2].
- [x] **Funding:** deployer **0.1 BNB** (phases 1+2 measured at 13.43M gas:
      0.00067 BNB at 0.05 gwei, 0.040 at 3 gwei); DMX owner **2.35 BNB**
      (2.261 BNB liquidity leg at the 2026-09-28 DMX price + gas + margin;
      it held 0.096 BNB that day). Re-check the leg on the morning with
      `script/fork/size-liquidity.ps1`.
      Done: deployer 0.1 BNB (P2); owner 2.384999 BNB against a 1.994 BNB
      leg re-priced that morning (P4) -- record: [Preflight][r-pre],
      [Step 5a][r-5a].
- [x] Contracts **verified** (source + constructors): on **Sourcify** with
      `script/launch/verify-sourcify.ps1` (free; rehearsed on the Chapel 2b
      deployment: 7/7 exact_match; `forge verify-contract --verifier
      sourcify` is NOT used: with forge 1.5.1 it reported "already
      verified" and verified nothing), and on **BscScan through the manual
      web form** (Solidity Standard-Json-Input; the script writes the
      input and the ABI-encoded constructor arguments per contract) -- the
      Etherscan API has no free tier for BNB Chain. Include the
      LiquiditySeeder.
      Done: Sourcify 7/7 `exact_match`; BscScan 7/7 Exact Match, confirmed
      by the operator -- record: [Step 4c][r-4c].
- [x] Timelock `MIN_DELAY` = **7 days**; `MIN_SUPPLY` = **21B**; fee cap 10%;
      `MAX_PAUSE_DURATION` = **14 days** -- confirmed on-chain post-deploy
      (the expiry parity line is covered by the verification above).
      Not a line of the launch record. The constants are compiled in, and
      the deployed bytecode matches the source exactly ([Step 4c][r-4c]);
      the 10 % cap is a literal in `setFees`, with no getter. Read from
      mined state on 2026-10-02 at block 125309256: `getMinDelay()` 604800
      (7 days), `MIN_SUPPLY()` 21e27 (21B), `MAX_PAUSE_DURATION()` 1209600
      (14 days).

## Liquidity

**Before deployment (Zenith #25)**

- [x] Check whether a DMN/WBNB pair already exists on the target factory.
      `initialize()` calls `createPair()` unconditionally and reverts if one
      exists — an observer can predict the proxy address and pre-create the
      pair to block the deploy.
      Done: none -- record: [Step 1][r-1].
- [x] The fix (using `getPair()` first) must be in the deployed
      implementation.
      Done: `git diff audit-final -- src/` empty ([Preflight][r-pre] P6),
      bytecode == source ([Step 4c][r-4c]).
- [ ] Consider private transaction submission as defence in depth.
      Not used: the session broadcast through the public `bsc-dataseed` RPC
      -- record: [Session][r-session]. The pair was absent right before
      phase 1 ([Step 1][r-1]), and the `getPair()` fix would have adopted a
      pre-created one.

**Initial liquidity pricing (Zenith #17)**

The pair is not fee-exempt, so it receives the NET amount while the router
calculates from the gross. Computing the BNB contribution from the gross DMN
input initializes the pool at the wrong price.

- [x] Calculate the BNB contribution from the DMN the pair ACTUALLY
      receives, not from the amount sent.
      Done: GROSS, NET and the 1.994 BNB leg sized live ([Step 5a][r-5a]);
      the pair's DMN reserve == NET exactly ([Step 5b][r-5b]).
- [x] Verify the resulting reserve ratio matches the intended opening price
      before proceeding.
      Done: opening price 415454175 against DMX 415454176 wei/token
      (0.0024 ppm) -- record: [Step 5b][r-5b].
- [x] Do NOT blanket-exempt the pair or the router as a workaround — it
      would disable fees on all buys and sells, and enable fee-free
      transfers through liquidity removal.
      Held: no exemption was granted; the pair charges 4 % both ways,
      measured on the bot's trades -- record: [Step 9][r-9].

**LP tokens to the Timelock (launch order step 6, merged into 5b)**

- [x] The LiquiditySeeder mints ALL the LP tokens of the DMN/WBNB pair
      directly to the Timelock inside the seed transaction (hash in the
      launch record): no project wallet ever holds them. The seeder is
      single-use (`used`), owner-only, keeps nothing (asserted in the call)
      and refuses an opening price more than 0.10 % off the intended one.
      Why a contract: 1 wei of WBNB + `sync()` on the empty pair makes the
      router's `addLiquidityETH` revert, and a non-atomic direct add can be
      `skim()`-ed (docs/MAINNET_FORK_RESULTS.md, F5b.P1 and runs H2/I).
      Done: exactly one LP mint to the Timelock, 97828093424055675223914, in
      tx `0xdc8dd206...dfa4`; the seeder `used`, holding nothing -- record:
      [Step 5b][r-5b].
- [x] Post-broadcast assert, from mined state: `pair.balanceOf(provider) ==
      0`, `pair.balanceOf(deployer) == 0` and `pair.balanceOf(timelock) ==
      pair.totalSupply() - MINIMUM_LIQUIDITY` (the 1000 wei PancakeSwap locks
      at pair creation). No project wallet holds LP; the Timelock holds all
      of it (rehearsed: docs/CHAPEL_2B_RESULTS.md, H1.14, with the old
      separate transfer; docs/MAINNET_FORK_RESULTS.md, runs H2 and I, F6.1,
      through the seeder: exactly one LP mint to the Timelock in the seed
      transaction, clean pair and griefed pair alike).
      Done -- record: [Step 5b][r-5b]; unchanged at [Step 8][r-8].
- [x] From here the pool can be withdrawn only by proposal -> vote -> queue
      -> 7-day timelock -> execute (docs/TREASURY_POLICY_v1.0.md, section 2).
      **In force**: the Timelock still held exactly the minted LP after the
      incident -- record: [Incident][r-inc], [Step 8][r-8].

**Automation state at launch (Zenith #27)**

- [x] Automation (fee swap and buyback) must be DISABLED or the fail-open
      fix deployed before the pair has reserves. An attacker can donate
      ~1 BNB to the token contract before initial liquidity and block the
      launch.
      Done: the fix is in the deployed code ([Preflight][r-pre] P6,
      [Step 4c][r-4c]); before the seed, reserves 0/0, token BNB 0, no
      donation -- record: [Step 4][r-4].
- [x] Verify both reserves are non-zero and all recipients functional before
      enabling automation.
      Done: both reserves > 0, automation flags on ([Step 8][r-8]); the
      first conversion ran end to end, staking notify included, in the
      bot's transaction ([Incident][r-inc]).

**One pool only: DMN/WBNB on PancakeSwap V2**

- [x] Create a single DMN/WBNB pair — this is the pair the fee-swap and
      buyback mechanisms operate on.
      Done: `0x40A97Ae210a44057603186B4BE92BAe719342AFA`, created by
      `initialize` -- record: [Step 2][r-2].
- [x] Do NOT create additional pools (DMN/USDT, DMN/BUSD or others). They
      would fragment liquidity, and the automated swap only operates on one
      pair. Routing through WBNB already lets anyone buy with any token.
      Held: `getPair` DMN/USDT and DMN/BUSD = `0x0` -- record: [Step 7][r-7].
- [x] Verify the pair address stored in the contracts matches the pair
      actually created on mainnet,
      `0x40A97Ae210a44057603186B4BE92BAe719342AFA`; a wrong address breaks
      fee-swap and buyback silently.
      Done: the pair `initialize` created ([Step 2][r-2]) == the factory's
      `getPair(DMN, WBNB)` ([Step 7][r-7]).

**Decisions to make and document before launch**

- [x] Initial liquidity amount -- DECIDED, decision (c): the largest single
      addLiquidityETH under the DMN 5B maxTx cap (~4.8B net; at the
      2026-09-10 DMX price of 4.69e-10 BNB/token, 2.2512 BNB; at the
      2026-09-28 price of 4.71191826e-10, 2.261 BNB -- re-priced
      live on launch day). Thin liquidity makes each fee-swap conversion
      move the price (about -7.8% per 0.2B chunk at that pool, by
      arithmetic); further depth comes from the treasury by proposal.
      On the day: 1.994 BNB at 415454176 wei/token -- record:
      [Step 5a][r-5a].
- [x] What happens to the LP tokens -- DECIDED: held by the Timelock,
      withdrawable only by vote + 7 days. Minted straight to the Timelock
      by the LiquiditySeeder in the 5b transaction (launch order 5b/6);
      the Timelock's LP position grows with every swap's fee. The earlier
      options (third-party lock with a stated duration, or burn) are
      superseded: the Timelock IS the verifiable lock, with no platform
      risk and no expiry.
      Done -- record: [Step 5b][r-5b].
- [x] Sequence relative to the migration window: opening trading before
      holders have migrated means the price forms on minimal volume. Decide
      and announce the order.
      Decided and done: trading first, at the seed (5b, 03:45:59 UTC), then
      the window (11b, 20:06:24 UTC) -- record: [Step 5b][r-5b],
      [Step 11a, then 11b][r-11]. The price did form on minimal volume:
      DMN 15.6 % below DMX at [Step 8][r-8]. Both announced together on
      2026-09-30 (docs/REGISTRO_POST.md).

**After deployment**

- [x] Verify a small test swap triggers the fee correctly (4%) and that
      accumulated fees reach the threshold path as expected.
      Verified without the test swap (launch step 9 **SKIPPED**): the 4 %
      checked to the wei on the MEV bot's real buy and sell, and the
      threshold path ran in the same transaction (0.2 B converted) --
      record: [Step 9][r-9], [Incident][r-inc].
- [ ] Confirm the buyback path executes on a real pool with real slippage —
      this is the least-proven surface, flagged in the protocol paper and to
      every auditor.
      **OPEN**: not yet exercised. The buyback fires only above 1 BNB in the
      token, which held 0.027083 BNB at [Step 8][r-8] and the same on
      2026-10-02 (block 125309256).

## dApp

- [x] **`NEXT_PUBLIC_CHAIN_ID=56`** in the Vercel production env: automatically
      turns off `noindex` and the "test environment" banner, and makes the
      mainnet RPC/explorer/addresses cascade (fill in `BSC_MAINNET` in
      `daimon-dapp/src/config/contracts.ts`, including the PancakeSwap pair
      read from `daimonV2.uniswapV2Pair()`).
      Done: production on chain 56 at app.daimon.money -- record:
      [Status][r-status], [Remaining][r-rem].
- [x] Re-enable Deployment Protection if the URL must stay private on staging;
      for the public launch, official domain + WalletConnect allowlist.
      Done: official domain app.daimon.money ([Status][r-status]);
      app.daimon.money is on the WalletConnect/Reown allowlist -- a
      WalletConnect connection to app.daimon.money from a phone succeeded
      on 2026-10-03.

## Fee automation (post-fix Zenith #1)

- [x] **Monitor the token contract's DMN balance** after launch:
      `balanceOf(DaimonV2)` is the fee inventory not yet converted.
      **In force**: the monitor runs on mainnet and reported the incident --
      record: [Status][r-status].
- [x] Once it exceeds `minimumTokensBeforeSwap`, a **1-wei DMN transfer to
      the pair**, from any address, triggers the conversion (at most one
      fee-swap chunk and one buyback slice per block: #28 budgets). The
      buyback BNB moves the same way — and only this way: sales through the
      router no longer trigger anything.
      First exercised by the MEV bot, not by the project -- record:
      [Incident][r-inc].
- **NOT a security requirement**: if the poke stops, fees simply
  accumulate — no deadline, no loss; conversion resumes with the next
  poke. Full model and rationale in THREAT_MODEL.md §8
  (⚠️ do not "fix" this by reintroducing the sell trigger: it would
  reopen finding #1).

## Post-launch governance

- [x] `marketingWallet` and `stakingContract` stay modifiable **only** via
      proposal → vote → queue → 7-day timelock → execute (no EOA path).
      **In force**: the Timelock is the only GOVERNANCE_ROLE holder and the
      only staking governance -- record: [Step 3][r-3].
- [ ] Guardian renewal/rotation before the 36-month expiry, if desired, via
      governance.
      **OPEN**, not due: the guardian expires 2029-09-28 01:08:32 UTC --
      record: [Step 2][r-2].

## Domain and dApp distribution

**Primary — traditional domain + Vercel**

- [x] Register a conventional domain (.io / .com / .xyz).
      Done: daimon.money -- record: [Status][r-status].
- [x] Point it to the Vercel deployment.
      Done: app.daimon.money -- record: [Status][r-status].
- [x] Set `NEXT_PUBLIC_CHAIN_ID=56` (this alone removes the noindex tag and
      the testnet banner).
      Done -- record: [Status][r-status].
- [x] Add the new domain to the WalletConnect/Reown allowlist.
      Done: app.daimon.money is on the allowlist -- a WalletConnect
      connection from a phone succeeded on 2026-10-03.
- [ ] Update every link: README, org profile, protocol paper, social channels.
      README done (`de50a49`, 2026-09-30: mainnet status, address table,
      daimon.money and app.daimon.money as official channels). Social
      channels done (checked 2026-10-09): the X profile (bio and website
      field) and the descriptions of the three Telegram channels/groups name
      daimon.money and app.daimon.money. **OPEN** (checked 2026-10-09):
      the GitHub org profile README (`daimon-dao/.github`) still describes
      the testnet status and the audit as "in preparation", links whitepaper
      v0.1 and lists no daimon.money link; the org "website" field is empty
      and the repository "homepage" field still points at
      daimon-dao.vercel.app; the protocol paper (v0.2) names only the
      repository, not daimon.money or app.daimon.money.
- [x] Announce the official domain explicitly and repeatedly: at launch,
      clone sites will appear.
      Done at launch: the 2026-09-30 announcement names daimon.money and
      app.daimon.money as the only official websites (docs/REGISTRO_POST.md).
      **In force**: keep repeating it.

**Mirror — decentralised, censorship-resistant**

Built after launch: the mirror is documented in docs/IPFS_MIRROR.md; the
current version is v2 (tag `mirror-v2`, commit `1cccf9d`, published
2026-10-09).

- [x] Register a blockchain domain (Unstoppable Domains: .crypto, .x)
      Done: `daimon.blockchain` (Unstoppable Domains, owned by the Brand
      account) -- docs/IPFS_MIRROR.md, "Unstoppable Domains".
- [x] Export the dApp as a static site and publish it to IPFS
      Done: static build target `npm run build:ipfs`, built in a container
      so that anyone can reproduce the CID; v2 = tag `mirror-v2`, CID
      `bafybeidmjrqs56gw4vqlnqptv4fungoayec6do7oojstfmoxjzidd6kvyq` --
      docs/IPFS_MIRROR.md, "Mirror v2" and "Reproducible build".
- [x] Pin the content (Pinata, Web3.Storage or equivalent) — unpinned IPFS
      content becomes unavailable
      Done: pinned on Filebase and on Lighthouse (CAR imports, CID
      preserved); v1 stays pinned as the previous version --
      docs/IPFS_MIRROR.md, "Mirror v2" and "Pinning".
- [x] Point the blockchain domain to the IPFS hash
      Done: `dweb.ipfs.hash` and `ipfs.html.value` of `daimon.blockchain`
      set to the v2 CID, Polygon tx `0x38d1fa67…eac149` (2026-10-09), read
      back from the registry and resolved in Brave -- docs/IPFS_MIRROR.md,
      "Mirror v2".
- [x] Verify the static export does not break: the i18n cookie and the wagmi
      SSR state currently rely on server-side rendering, which a static
      export removes
      Done: the locale cookie is replaced by the browser's stored choice
      applied after hydration, the wagmi cookie store by its default
      `localStorage` store with reconnect after mount; checked in the
      browser against a local fork with a mock wallet (`daimon-dapp/e2e`)
      and on the published CID -- docs/IPFS_MIRROR.md, "What a server used
      to do" and "Testing locally".

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

**ON HOLD** (note of 2026-10-09). A crypto-specialised lawyer was consulted
in August 2026; the legal front at launch is the worldwide disclaimer
(DISCLAIMER_TERMS v0.3: docs/DISCLAIMER_TERMS_v0.3_EN.md, authoritative,
with the Italian courtesy translation) and the public team holdings
statement (docs/TEAM_HOLDINGS.md). The entity structure is deferred by
decision of 2026-09-12, among the last steps; the treasury accumulates
untouched meanwhile. A MiCA opinion was requested from an external law firm
on 2026-08-24 and no reply has been received; it is on hold together with
the entity, as is the tax review. The four items below stay unticked until
the entity question is reopened.

- [ ] **ON HOLD** — Consult a crypto-specialised lawyer before mainnet
      deployment — not to incorporate, but to understand exposure,
      obligations and token classification under local and EU regulation
      (MiCA)
- [ ] **ON HOLD** — Revisit the question of a legal structure once the
      protocol is live and the treasury can fund it. A structure decided by
      DAO vote and paid from protocol revenue is more coherent with the
      project than one funded personally in advance.
- [ ] **ON HOLD** — Confirm the protocol paper disclaimer (Section 14) is
      adequate for the jurisdictions where the interface is accessible
- [ ] **ON HOLD** — Review tax obligations arising from protocol operations
      and treasury holdings

Contracts requiring an identifiable counterparty — audits, listings, service
agreements — are signed by an individual member of the DAO. That is normal
for unincorporated projects, and the data stays with the counterparty. It
does not make the protocol any less ownerless: no signer holds any privileged
role on-chain.

---

**Freeze:** the contracts in `src/` are frozen at tag `audit-final`. Any
change to the contracts before mainnet requires a new tag and re-running the
checks. Held at launch: `git diff audit-final -- src/` empty on the morning
-- record: [Preflight][r-pre], P6.

## Contract upgradeability — read before planning any fix

DaimonV2 is behind a UUPS proxy and can be upgraded by governance.
DaimonGovernor, DaimonTimelock and DaimonStaking are NOT upgradeable.

Any correction to the non-upgradeable contracts must be deployed before
mainnet. Afterwards it would require redeploying them and rewiring every
role and immutable reference — DaimonGovernor stores the Staking address
immutably.

[rec]: docs/MAINNET_LAUNCH_RECORD.md
[r-status]: docs/MAINNET_LAUNCH_RECORD.md#status----migration-window-open
[r-rule]: docs/MAINNET_LAUNCH_RECORD.md#the-owner-key-rule----for-the-whole-migration-window
[r-session]: docs/MAINNET_LAUNCH_RECORD.md#session
[r-pre]: docs/MAINNET_LAUNCH_RECORD.md#preflight----2026-09-29-block-124622368
[r-1]: docs/MAINNET_LAUNCH_RECORD.md#step-1----no-pair-block-124623493-re-run-at-124626008-right-before-22
[r-2]: docs/MAINNET_LAUNCH_RECORD.md#step-2----phase-1-and-phase-2-deployer-ledger
[r-3]: docs/MAINNET_LAUNCH_RECORD.md#step-3----verification-passed-3636-block-124627634
[r-4]: docs/MAINNET_LAUNCH_RECORD.md#step-4----automation-inert-block-124633823
[r-4b]: docs/MAINNET_LAUNCH_RECORD.md#step-4b----liquidityseeder-deployer-its-last-transaction
[r-4c]: docs/MAINNET_LAUNCH_RECORD.md#step-4c----verification
[r-5a]: docs/MAINNET_LAUNCH_RECORD.md#step-5a----the-owner-claims-gross-metamask-via-bscscan
[r-5b]: docs/MAINNET_LAUNCH_RECORD.md#step-5b-step-6-merged----the-seed
[r-inc]: docs/MAINNET_LAUNCH_RECORD.md#incident----a-bot-captured-the-first-fee-conversion-during-the-pause
[r-7]: docs/MAINNET_LAUNCH_RECORD.md#step-7----one-pool-only-block-124754501
[r-8]: docs/MAINNET_LAUNCH_RECORD.md#step-8----re-baselined-after-the-incident-block-124757113-173157-utc
[r-9]: docs/MAINNET_LAUNCH_RECORD.md#step-9----skipped-decision-the-4--fee-verified-on-the-bots-trades
[r-10]: docs/MAINNET_LAUNCH_RECORD.md#step-10----skipped-decision
[r-pre11]: docs/MAINNET_LAUNCH_RECORD.md#before-11a----state-against-the-step-8-baseline-block-124764744-182911-utc
[r-11]: docs/MAINNET_LAUNCH_RECORD.md#step-11a-then-11b----the-window-opens-dmx-owner-metamask-via-bscscan
[r-post11]: docs/MAINNET_LAUNCH_RECORD.md#after-11b----the-post-11b-checks-block-124778183
[r-rem]: docs/MAINNET_LAUNCH_RECORD.md#remaining
