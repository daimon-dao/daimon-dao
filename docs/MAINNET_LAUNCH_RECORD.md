# Mainnet launch record -- BNB Smart Chain (chainId 56)

The launch journal of Daimon DAO, run step by step from `docs/LAUNCH_DAY.md`
(master `9c4af2a`, code at tag `launch-config-rc2`). Every value below was
read back from mined state after the step, before the next one.

## Status -- PAUSED

| | |
|---|---|
| paused at | 2026-09-29 04:48 UTC, block 124655356 |
| **last step done** | **5b (with step 6 merged)** -- the pool is open, the LP is the Timelock's |
| **next step** | **7** (read-only), then 8 (read-only), 9 (owner, 3 tx), 10 (owner), 11a + 11b (owner) |
| pending transactions | **none** -- deployer nonce 20 latest = pending; owner nonce 1011 latest = pending |
| migration window | **CLOSED** (11a/11b not done): `_maxTxAmount` 1.5e27, `isExcludedFromFee(TL)` false -- every claim reverts `AmountMismatch` |
| deployer | done: nonce 20, 0.099291 BNB, signs nothing more |
| DMX owner | nonce 1011, 0.390959 BNB, 0 DMN; `owner()` = itself, `getUnlockTime()` 0 |
| dApp | branch `dapp/mainnet`, published only at 11b; its preview is confirmed before 11b |
| monitor | live on mainnet |

**To resume:** `. .\script\launch\resume-56.ps1` (every address and fixed
value, no secrets), re-read the "expected at resume" block in it, then step 7.
The DMX owner must NEVER call `lock()`, `renounceOwnership` or
`transferOwnership` on DMX until 11b is done.

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

## Remaining

| step | who | status |
|---|---|---|
| 7 one pool only | read-only | NEXT |
| 8 reserves / automation | read-only | |
| 9 test swap (9.1 buy 0.001 BNB, 9.2 approve, 9.3 sell half) | owner | |
| 10 first poke (`transfer(PAIR, 1)`; expected to convert nothing) | owner | |
| dApp preview confirmation | operator | before 11b |
| 11a `setMaxTxAmount(1e30)` then 11b `excludeFromFee(TL)` | owner | the window opens at 11b |
