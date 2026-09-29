# Mainnet launch record -- BNB Smart Chain (chainId 56)

The launch journal of Daimon DAO, run step by step from `docs/LAUNCH_DAY.md`
(master `9c4af2a`, code at tag `launch-config-rc2`). Every value below was
read back from mined state after the step, before the next one.

## Status -- MIGRATION WINDOW OPEN

| | |
|---|---|
| **window opened** | **2026-09-29 20:06:24 UTC**, block 124777699 (11b) |
| **window closes** | `migrationDeadline` **1798420124** = 2026-12-28 01:08:44 UTC |
| launch sequence | **complete**: steps 1-8 and 11a/11b done; 9 and 10 SKIPPED by decision (see below) |
| pending transactions | **none** -- deployer nonce 20; owner nonce 1013 latest = pending (block 124778497) |
| deployer | done: nonce 20, 0.099291 BNB, signs nothing more |
| DMX owner | nonce 1013, 0.390956 BNB, 0 DMN; `owner()` = itself, `getUnlockTime()` 0 -- bound by the owner-key rule below |
| dApp | live on mainnet at app.daimon.money (production, chain 56) |
| monitor | live on mainnet; it reported the incident below |
| repository | pushed: the journal commits (`ce218b1`, `483c83b`, `90d79cf`) merged with origin as `fae8be6`, pushed to `origin/master` (`0a65087..fae8be6`) on 2026-09-29 21:35:47 UTC |

### The owner-key rule -- for the WHOLE migration window

Until the window closes (`migrationDeadline` 1798420124, 2026-12-28 01:08:44
UTC), the DMX owner `0xF8EC459CAEaF1052b64B38BDD67290B0c132B0Ae` must NOT call,
on DMX `0x36EbA94407B53c631eE822C219e94580fadd67c7`:

- `lock(...)` -- it sets `owner()` to zero until `unlock()`: nobody could
  restore the two settings below while the immutable deadline keeps running;
- `renounceOwnership()`;
- `transferOwnership(...)`;
- `includeInFee(0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891)` -- removing the
  Timelock's exemption closes the window: every claim reverts `AmountMismatch`;
- `setMaxTxAmount(x)` with `x` below `1000000000000000000000000000000` (1e30)
  -- a lower cap makes claims above it revert.

(And never `presale(true)`: it lifts DMX's fee and cap for everyone.)

**To resume a session:** `. .\script\launch\resume-56.ps1` (every address and
fixed value, no secrets).

Evidence copied out of the session into `docs/launch-56/`: the step-3 output,
the phase journals (`broadcast-phase1/`, `broadcast-phase2/`), the state file
`two-phase-56.json`, the failed first 2.2 attempt, and the session setup files.

## Session

- RPC: `https://bsc-dataseed.bnbchain.org` (prunes old state: reads pinned to
  a past block fail with `missing trie node`; per-transaction legs are read
  from receipts instead). Gas price of the day: 0.05 gwei (`$GP` = 50000000).
- `.env`: `MIGRATION_DURATION=7776000`; `GUARDIAN_ADDRESS`, `MARKETING_WALLET`,
  `TREASURY_ADDRESS` empty.
- The Claude session's PowerShell tool keeps no variables between calls: the
  setup (`session.ps1`) and step 2's environment (`step2-env.ps1`, which also
  refuses to continue unless `GUARDIAN_ADDRESS` is the mainnet Safe) were
  dot-sourced in the same call as every forge command.

## Preflight -- 2026-09-29, block 124622368

| # | result |
|---|---|
| P1 | deployer nonce 0 |
| P2 | deployer 0.1 BNB |
| P3 | first run: `Ledger device not found` (device not connected) -- STOP; after connecting: `P3 OK: 0x4D38...a26e at m/44'/60'/9'/0/0` |
| P4 | leg 1.994 BNB, owner 2.384999 BNB -> FUNDED |
| P5 | `owner()` = owner, `getUnlockTime` 0, owner fee-exempt, `_maxTxAmount` 1.5e27 |
| P6 | `launch-config-rc2-2-g9c4af2a`; `git diff audit-final -- src/` empty; 203/203 tests |
| P7 | all five paths absent |
| P8, P9 | confirmed by the operator (BscScan Write tabs of DMX and the router; MetaMask hex data on) |

Environment resolution, proved by a throwaway probe making phase 1's seven
`vm.envOr` calls: with step 2's shell variables, guardian = the Safe
`0x37F4...c7a8`, router = PancakeSwap v2, `OLD_DAIMON` = DMX, 90 days, no
override. **Without them, `.env`'s empty `GUARDIAN_ADDRESS` resolves to the
deployer, the router to the testnet router, and a mock old token would be
deployed.** The Safe on chain: Safe proxy, threshold 2, owners
`0xD9dB...fc16`, `0xdFfe...687f`, `0xacA4...0F9b`.

## Step 1 -- no pair (block 124623493, re-run at 124626008 right before 2.2)

`$PROXY` = `0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a`; `getPair` = `0x0`.

## Step 2 -- phase 1 and phase 2 (deployer, Ledger)

**2.1** simulated twice (the second after `forge build --force`, to drop a
stale cache entry left by the probe): byte-identical transactions, 90 days,
treasury and marketing = predicted Timelock, guardian `0x37F4...c7a8` in the
`initialize` calldata, no warning.

**2.2, first attempt -- FAILED, nothing sent.** The Ledger answered
`APDU 6a80 (INVALID_DATA)` to the first deploy (5 tries, 01:04:03-01:04:18
UTC): Blind signing was disabled in the Ethereum app. P3 cannot detect this (it
only reads the address). Nonce stayed 0, no code at the predicted addresses;
the journals of the attempt were moved aside (`docs/launch-56/failed-2.2-attempt1/`)
and a FRESH 2.2 was run after enabling Blind signing.

**2.2 -- phase 1**, all status 1, from the deployer:

| nonce | contract | address | block (UTC) | tx |
|---|---|---|---|---|
| 0 | DaimonV2 implementation | `0xA7bC2D4D35e49bdfC8329e3673d7De520832941c` | 124626062 (01:08:24) | `0xbaa588bc9d08a6b6ad7fd3c57f9bae0f7be9c4869c378ad429524fb5fbeb5a6e` |
| 1 | DaimonV2 proxy (DMN) | `0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a` | 124626081 | `0x2bd250046301cdf01f23a7bcc5d24cc5ed8462430dd239f9a0d231ad937267b9` |
| 2 | DaimonMigration | `0x76368b60514b145617385847aCFF7b7EA9764725` | 124626108 (01:08:44) | `0xa5a7a4c1cbe89404e9cdb7396af06c8f1f0f276fc0064198efe07a83a1df4eba` |

Deadline: Migration block timestamp 1790644124 + 7776000 = **1798420124**
(2026-12-28 01:08:44 UTC) == `migrationDeadline()`, exactly. Pair created by
`initialize`: `0x40A97Ae210a44057603186B4BE92BAe719342AFA`.

**2.3 -- phase 2**, 16 transactions, nonces 3-18, blocks 124626867 (01:14:26)
to 124627202 (01:16:57), all status 1; `All decentralization asserts passed`.

| nonce | call | tx |
|---|---|---|
| 3 | CREATE DaimonTimelock `0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891` | `0xc80fe87e796c03e48b68d2602f0f0d7e696d57345acf752c5a59724720893f10` |
| 4 | CREATE DaimonStaking `0xBb596e7308D6C5AED55cEC597D372840Cbe575b1` | `0xe4cb0d2b0917c965010194bbee7ac9789843d7a4cb6ee754e314e43b52accf32` |
| 5 | CREATE DaimonGovernor `0x1397a7d25595B718BE6FEEDd42ed5E60F66E16De` | `0xa4f0b38c691e60c85e936e791d8cc7a8158fb5579dc79984e0014533fe2ab2c2` |
| 6 | Timelock `grantRole` | `0x1522d3a945c85c02ffb8a7c21d5f289d0ab144312de0a598f3066a5f116d690e` |
| 7 | Timelock `grantRole` | `0x99dc74d9d3ce7bda821ce3a1ffd5a71d96df65052609ae2a89a4394f01df0834` |
| 8 | Timelock `grantRole` | `0x12cbb0df3db4653176974795b6718febd703401a5d10cf28c3dc6db3659a94df` |
| 9 | Timelock `revokeRole` | `0xcb783b4dba9bf99dc3445a64f93e1ac70d3e74af1ce0b0294fe5d0f65144b844` |
| 10 | Timelock `revokeRole` | `0xcc7e084016a50bbe3c548046ecf9af3172c4268f69cec9223572d404854ba90c` |
| 11 | Staking `setGovernance` | `0xae888a6d5aee9e2620a24e06240465ce19e36d3f20ab14c1674867142533a732` |
| 12 | Staking `setGovernance` | `0x4a732cf6c758efe7dd7abee933e0a682d4ea0ea14f59cf61543b4657e9f568d9` |
| 13 | DMN `setStakingContract` | `0xd94477efbb8617b2e908375d57aa747ff4d17cb048e880dec050067475cf0c38` |
| 14 | DMN `setStakingRewardShareBps` | `0xbe3dda1245751170d31b83e8f5394d53742a7f776ef272f6f30324a837174784` |
| 15 | DMN `setFees` | `0x0e486b53cf9f2b65f34ec78a150e9f814e32c8e2044b1849943e336af102bcca` |
| 16 | DMN `grantRole` | `0x6f556ef8be8a0f2795798f9987f7890ab5b6109137fd55dc55d94f24e843701d` |
| 17 | DMN `revokeRole` | `0x0664428688998467ed9bb1acbf5bfc44572bedf431080581f4588c15730fba42` |
| 18 | Timelock `renounceRole` | `0x769342a6523e4c6e91a877b127de3732dd28816ea8d3cccb96c7ea8fe8b20755` |

Fees 10/10/20 (liquidity 30); guardian expiry 1885252112 (2029-09-28 01:08:32
UTC) on token, Timelock and Governor; deployer nonce 19; phase 1 + 2 cost
0.000672 BNB.

## Step 3 -- VERIFICATION PASSED: 36/36 (block 124627634)

Exit 0. Full output: `docs/launch-56/step3-verify-deploy-56.txt`.

## Step 4 -- automation inert (block 124633823)

`swapAndLiquifyEnabled` true; token's own DMN 0; pair reserves 0/0; token BNB 0;
pair LP supply 0, no donation.

## Step 4b -- LiquiditySeeder (deployer, its last transaction)

`0x21ab79825b86137CF1b04884FCFC4e4b717ce062`, nonce 19, block 124634080
(02:08:33 UTC), gas 755,546, tx
`0x14548b14cd96323d518d85db43da15b2ae3524e152b0a858c180af38145b35ee`.
Getters: `owner` = DMX owner, `dmn` = DMN, `pair` = pair, `wbnb` = WBNB,
`timelock` = Timelock, `used` = false.

## Step 4c -- verification

Sourcify: 7/7 `exact_match` (creation and runtime), compiler
0.8.26+commit.8a97fa7a. BscScan: the operator confirmed all 7 verified (Exact
Match), DMN with Read/Write as Proxy, seeder `owner` = the DMX owner and `used`
= false. (BscScan served a Cloudflare challenge to the session's browser; the
BscScan checks were the operator's.)

## Step 5a -- the owner claims GROSS (MetaMask via BscScan)

Non-owner check (block 124637760), from a real DMX holder chosen by the
operator (an EOA, not the owner, not fee-exempt, holding more than 1 B DMX;
address not recorded here): `claim(1e27)` with the allowance by state
override reverts `0x55e97b0d` (`AmountMismatch`); without the override,
`ERC20: transfer amount exceeds allowance`. `isExcludedFromFee(TL)` false.

Sizing (live token, block 124637790): DMX price 415454176 wei/token;
**GROSS 4999548574361503910682398180, BNB leg 1994000000000000000 (1.994),
NET 4799566631387043754255102254**; owner 2.384999 BNB -> FUNDED.

| # | call | block (UTC) | tx | check |
|---|---|---|---|---|
| 5a.1 | DMX `approve(MIG, GROSS)` | 124640449 (02:56:19) | `0x13e8f591acef7941a491c9cf9dbb09d79df1d90428d27b77e5a1f7e88ea36c07` | input == expected; allowance == GROSS |
| 5a.2 | Migration `claim(GROSS)` | 124642589 (03:12:23) | `0x39b44eab12057cd2396cbc1200e45bc89f9b2bd9623cc717a4c5557af4889549` | input == expected; in the receipt DMX owner->TL == GROSS, DMN MIG->owner == GROSS, `Claimed` == GROSS; `migratedAmount` = `totalMigrated` = owner DMN = `DMX.balanceOf(TL)` = GROSS |

## Step 5b (step 6 merged) -- the seed

| # | call | block (UTC) | tx | check |
|---|---|---|---|---|
| 5b.1 | DMN `approve(SEEDER, GROSS)` | 124644973 (03:30:16) | `0x942150b894a8f94482feb79352a18f76369bb4459552cbfd8094bf79cdb6ab0e` | input == expected; allowance == GROSS; an eth_call of `seed` from the owner with 1.994 BNB succeeded before signing |
| 5b.2 | Seeder `seed(GROSS)`, value 1.994 BNB | 124647068 (03:45:59) | **`0xdc8dd206e10e5293e7380163d13d3f4bb5575662d0eddef99f9bddd7f7b8dfa4`** (the seed transaction, to publish) | see below |

- reserves: DMN `4799566631387043754255102254` == NET; WBNB `1994000000000000000` == BNB (no dust);
- opening price 415454175 vs DMX 415454176 (0.0024 ppm);
- exactly ONE LP `Transfer(0x0 -> TL)` = `97828093424055675223914` ==
  `pair.balanceOf(TL)` == `totalSupply - 1000` (the other LP Transfer is the
  1000 minimum liquidity to 0x0);
- LP of owner 0, of deployer 0 -- **step 6 done**;
- seeder `used` true, holds 0 BNB / WBNB / DMN / LP; owner's allowance to it 0;
  owner's DMN 0;
- fee inventory `DMN.balanceOf(TOKEN)` = `149993992418992321497667254` (~0.15 B);
  Timelock BNB 0, token BNB 0.

At the pause (block 124655356) the reserves are unchanged since the seed (no
trade yet); `DMX.balanceOf(TL)` = `totalMigrated` = GROSS.

## Incident -- a bot captured the first fee conversion (during the pause)

On resuming (17:12 UTC) the "expected at resume" values no longer held: pair
reserves, fee inventory, token BNB and the Migration's DMN had moved. The
monitor identified the cause. Everything happened in ONE atomic transaction:

| | |
|---|---|
| tx | `0xa1238092425b7c1cc0840568d1ce9fe7534f842e584555049df353363f2ed048` |
| block / time | 124657486, **2026-09-29 05:04:08 UTC** (1h18m after the seed, 16 min after the pause snapshot) |
| actor | contract `0x818fF7dbfF345390F27E7C6EA209D3b1be8bf900` (3,247 bytes), called by the EOA `0xfc3facd67138966ab0c841e905b0c4bca1abe92f` (EIP-7702-delegated, nonce 749 at the time) |
| gas | 1,104,173 at 0.05 gwei; tx index 188 |

The sequence, from the 40 logs of the receipt:

1. Flash-borrows 0.022 WBNB from another V2 pair (`0x16b9a82891338f9ba80e2d6970fdda79d1eb0dae`).
2. **Buys** DMN from the launch pool through the router: 0.022 BNB -> gross
   52,246,707.98 DMN out of the pair; 50,156,839.66 to the bot, 1,567,401.24
   (3 %) to the token's fee inventory, 522,467.08 (1 %) reflected.
3. **Stakes 1 wei**, lock option 0 (30 days, 1x): voting power **1**, the
   whole `totalVotingPower`. Lock ends 2026-10-29 05:04:08 UTC.
4. **Donates 48,438,526.78 DMN directly to the token contract**, lifting the
   fee inventory (about 0.150 B + 0.0016 B from its buy) past the 0.2 B
   `minimumTokensBeforeSwap`.
5. Sells the remaining 1,718,339.22 DMN through the router for 0.000699 BNB
   (a router-initiated transfer skips the automation, by design, finding #1).
6. **Pokes**: a 1-wei direct transfer to the pair triggers
   `_swapAccumulatedFees(0.2 B)`: 200,000,000 DMN sold for 0.081248 BNB.
7. The conversion splits: marketing branch 20/30 = **0.054165 BNB ->
   `notifyRewardAmount`** (`stakingRewardShareBps` 1000 = all of it to
   staking, 0 to the Timelock); buyback branch 10/30 = 0.027083 BNB stays in
   the token. With `totalVotingPower` = 1, **100 % of the notify accrues to
   the bot**.
8. **`claimReward`: 0.054165 BNB** to the bot, same transaction.
9. Repays 0.022055 WBNB to the flash lender.

Bot's net: 0.054165 + 0.000699 - 0.022055 = **about +0.0328 BNB** (gas
0.000055). The protocol's cost: the fee inventory accumulated at the seed
(5b) was converted early, and its staking share, which with no staker would
have gone to `zeroStakerReserve` (recoverable by governance), went to a
1-wei position. Side effects: the Migration's DMN grew by 50,527,491.68
(reflection of this volume); staking holds 1 wei of DMN and 0 BNB; the pool
price fell by about 5.9 %.

**Finding.** A 1-wei stake placed in the same transaction immediately before
a NEW notify captures 100 % of that notify while `totalVotingPower` is near
zero. The #35 guard (`zeroStakerReserve`, `DaimonStaking.sol:134-139`,
`338-344`) covers a BACKLOG received while nobody staked, not this: once any
voting power exists, `notifyRewardAmount` distributes pro rata
(`DaimonStaking.sol:349`) and `claimReward` pays at once (`380-390`). The
trigger is public by design (`DaimonV2.sol:573-577`: any direct transfer to
the pair once the inventory is >= 0.2 B), and a donation to the token
contract arms it. Source of the split: `DaimonV2.sol:705-723`. **Mitigation:
structural, once staking is populated**: stake cannot exit for 30 days, so a
position that captures a notify must stay locked, and against real voting
power a dust stake receives dust. The window is the empty-staking period
only.

**What the bot could and could not do** (read at block 124756368):

- Governance: **nothing**. Its voting power is 1 wei, below
  `proposalThreshold` 1000e18, so it cannot propose. `proposalCount` 0; no
  Timelock operation can exist (only the Governor is PROPOSER). Anyone who
  stakes >= 1000 DMN could propose and, with total voting power this small,
  clear the 10 % quorum alone, but the path is at least 13 days (1-day delay,
  5-day vote, 7-day Timelock) and the guardian Safe can cancel it on the
  Governor and on the Timelock at any stage until 2029-09-28.
- Rewards: **yes, not cancellable**. While it is the only staker it receives
  100 % of the staking share of every future conversion and can claim at any
  time. The guardian's only lever is `setPaused` (all DMN transfers, bounded
  window). Exposure now is small: the inventory is 51,554 DMN, and repeating
  the trick means donating the gap to 0.2 B, which costs more than one
  conversion's staking share (about 0.054 BNB at the day's price). Any real
  stake dilutes the 1-wei position to nothing.
- Its own 1 wei: withdrawable after 2026-10-29.

Nothing in the transaction touches DMX, the Migration's custody (window
closed), or the LP (the Timelock still holds exactly the minted
`97828093424055675223914`).

## Step 7 -- one pool only (block 124754501)

`getPair(DMN, WBNB)` = `0x40A97Ae210a44057603186B4BE92BAe719342AFA`;
`getPair(DMN, USDT)` = `0x0`; `getPair(DMN, BUSD)` = `0x0`.

## Step 8 -- re-baselined after the incident (block 124757113, 17:31:57 UTC)

| check | read |
|---|---|
| reserves | DMN `4948969529051442709553456167`, WBNB `1934053593848810506`, both > 0; last change 05:04:08 UTC (the bot) |
| pair `balanceOf` | DMN reserve + 1 wei (the bot's poke, after the sync), WBNB = reserve |
| fee inventory | `51553630463798540020259` (51,554 DMN), **0.026 % of the 0.2 B threshold** -- the runbook's "~0.15 B" no longer applies |
| automation | `swapAndLiquifyEnabled` true, `buyBackEnabled` true; token BNB 0.027083 (buyback fires only above 1 BNB) |
| staking | `totalVotingPower` 1 (the bot), 0 BNB, `zeroStakerReserve` 0 |
| Timelock | 0 BNB; LP `97828093424055675223914` == supply - 1000 |
| prices | DMN 390,799,252 wei/token; DMX **463,263,611** (it rose from 415,454,176 at sizing): **DMN is 15.6 % below DMX** |
| DMX | `owner()` = owner, `getUnlockTime` 0, `_maxTxAmount` 1.5e27, not fee-exempt: TL, MIG |

## Step 9 -- SKIPPED (decision); the 4 % fee verified on the bot's trades

Instead of the owner's test swap, the fee is verified exactly on the bot's
own buy and sell in tx `0xa1238092...d048`, to the wei:

| leg | gross | to the token (3 %) | reflected (1 %) | net | check |
|---|---|---|---|---|---|
| buy (pair -> bot) | `52246707983495916400064594` (== the pair's `Swap` amount0Out) | `1567401239504877492001937` == floor(gross x 30 / 1000) | `522467079834959164000645` == floor(gross x 10 / 1000) | `50156839664156079744062012` | net == gross - both floors: 96 % |
| sell (bot -> pair) | `1718339216557158019185944` | `51550176496714740575578` == floor(gross x 30 / 1000) | `17183392165571580191859` == floor(gross x 10 / 1000) | `1649605647894871698418507` (== the pair's `Swap` amount0In) | net == gross - both floors: 96 % |

4 % on both directions, not the historical 5 %.

## Step 10 -- SKIPPED (decision)

The inventory is 51,554 DMN, far below the 0.2 B threshold: a poke converts
nothing. The first conversion has already happened (the incident).

## Before 11a -- state against the step-8 baseline (block 124764744, 18:29:11 UTC)

After the operator published the dApp: reserves, last pair change (05:04:08),
fee inventory, staking (`totalVotingPower` 1), `proposalCount` 0, DMX owner /
unlock / cap / exemptions (owner yes, Timelock no, Migration no), owner nonce
1011, deployer nonce 20, Timelock LP and DMX, `migrationDeadline`, token not
paused -- all identical to the baseline.

## Step 11a, then 11b -- the window opens (DMX owner, MetaMask via BscScan)

| # | call on DMX | block (UTC) | tx | check |
|---|---|---|---|---|
| 11a | `setMaxTxAmount(1000000000000000000000000000000)` | 124767991 (18:53:34) | `0xfaef2123e54dd4d5054b9195284d43576e35c5161e178ae5e8b810f9b620b47b` | status 1, gas 28,742, 0 logs (no event on the real DMX); owner nonce 1011, 0 BNB; mined input **byte-identical** to `0xec28438a000000000000000000000000000000000000000c9f2c9cd04674edea40000000`; `_maxTxAmount()` == `1000000000000000000000000000000` exactly; `isExcludedFromFee(TL)` still false (window still closed) |
| 11b | `excludeFromFee(0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891)` | **124777699 (20:06:24)** | `0x8aaac289174a13a61040a68503550d79b31cdc25e1884686e8a42632f04cd54d` | status 1, gas 46,232, 0 logs; owner nonce 1012, 0 BNB; mined input **byte-identical** to `0x437823ec000000000000000000000000cdaa1cfe783a4de642ca3ed98a38bfdc16f30891` |

## After 11b -- the post-11b checks (block 124778183)

| check | read |
|---|---|
| `isExcludedFromFee(TL)` | `true` |
| `isExcludedFromFee(MIG)` | `false` |
| `_maxTxAmount()` | `1000000000000000000000000000000` (1e30) |
| claim of 2e27 (above the old 1.5e27 cap), eth_call from a real community holder with the allowance by state override | **succeeds** (before 11b: `AmountMismatch`) |
| claim of 1e27 (below the cap), same method | **succeeds** |
| DMX `owner()` / `getUnlockTime()` | the owner / `0` |
| owner nonce | 1013, latest = pending |
| `migrationDeadline` | `1798420124` (2026-12-28 01:08:44 UTC) |
| `totalMigrated` | GROSS (only the owner's 5a claim so far) |
| Timelock DMX | `5000411500717746005615697643` >= `totalMigrated` (reflection, as expected) |

A successful claim simulation means the Migration's own 1:1 check (the
Timelock's DMX delta == the amount) passes for a real holder with both the
exemption and the raised cap in effect. The holder is a community member:
its address is not recorded here.

From here, per LAUNCH_DAY.md "After 11b": for each `Claimed` event, the
Timelock's DMX delta in that transaction == the amount; the Timelock's DMX
is `>=` `totalMigrated`, never `==`.

## Deviations from LAUNCH_DAY.md

1. P3 failed once (Ledger not connected), passed after connecting.
2. 2.2 failed once at signing (Blind signing disabled), nothing sent; fresh 2.2
   succeeded. Proposed doc fix: P3's text already says "Blind signing enabled",
   but nothing checks it -- a signing-path check is worth adding.
3. The doc's `Remove-Item env:...` form is blocked by the session tool;
   `[Environment]::SetEnvironmentVariable(name, $null, "Process")` was used (same effect).
4. A stale forge cache entry (from the env probe) caused a warning in the first
   2.1; `forge build --force` removed it before the second 2.1 and 2.2.
5. The phase-1 script prints no guardian line; the guardian was read from the
   state file and the decoded `initialize` calldata.
6. During the pause a bot captured the first fee conversion (see Incident);
   the resume baseline no longer held, and steps 8-10 were re-planned.
7. Step 9 skipped: the 4 % fee verified on the bot's trades instead. Step 10
   skipped: nothing to convert.
8. Pair event history is not readable on the day's RPCs (dataseed refuses
   `eth_getLogs`; publicnode treats the range as an archive request): the
   incident was reconstructed from the transaction's own receipt.

## Remaining

| step | who | status |
|---|---|---|
| 7 one pool only | read-only | done |
| 8 reserves / automation | read-only | done (re-baselined) |
| 9 test swap | owner | SKIPPED -- fee verified on the bot's trades |
| 10 first poke | owner | SKIPPED -- inventory 51.5 K |
| dApp publication | operator | done: app.daimon.money, production on chain 56 |
| 11a `setMaxTxAmount(1e30)` then 11b `excludeFromFee(TL)` | owner | done -- **the window opened at 11b, 2026-09-29 20:06:24 UTC** |
| the owner-key rule | owner | in force until 2026-12-28 01:08:44 UTC (see Status) |
| push of the journal commits | operator | done -- merged as `fae8be6`, pushed `0a65087..fae8be6` on 2026-09-29 21:35:47 UTC |
