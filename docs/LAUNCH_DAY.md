# Launch day -- the script

Every command of the Daimon DAO mainnet launch, in order: who signs it,
what to check after it, and what to do when a check fails. Written from
what ran on a local fork of BSC mainnet against the REAL DMX, the REAL DMX
pool and the REAL PancakeSwap v2 router (docs/MAINNET_FORK_RESULTS.md,
2026-09-28), not from memory. The launch order is the one in
CHECKLIST_MAINNET.md; the protocol code is the tag `launch-config-rc1`
(`git diff audit-final -- src/` empty); the only new contract is the
launch tool `script/launch/LiquiditySeeder.sol`, outside `src/`.

Run references in brackets -- `[H2 F5b.1]` -- point at the journal row that
proves the step. Run **H2** is the reference run of this configuration (a
clean pair), run **I** the same day with the pair griefed first; runs C and
G are the earlier ones (C: the faithful stop at 5b on the owner's real
balance).

## 0. Decisions in force, and what is still open

| item | decision | proof |
|---|---|---|
| Step 5b | through the single-use `LiquiditySeeder`; the LP is minted DIRECTLY to the Timelock, so step 6 is merged into 5b | [H2 F5b.1, H2 F6.1], griefed: [I F5b.G, I F5b.1, I F6.1] |
| `MIGRATION_DURATION` | **90 days = 7776000 s**, set explicitly | [H2 F2.1, H2 F2.2b] |
| Deployer funding | **0.1 BNB** (ample) | [H2 F14.1] |
| DMX owner funding | **2.35 BNB** (2.261 BNB leg at the 2026-09-28 DMX price + gas + margin) | [C F5b.0, H2 F14.2] |
| Step 10 | the first poke converts nothing; the first conversion comes later | [H2 F10.1] |
| Verification | Sourcify via `script/launch/verify-sourcify.ps1` + BscScan manual web form | Chapel 2b: 7/7 exact_match |

**Open: the owner's balance.** On 2026-09-28 the DMX owner held 0.096153
BNB; 2.35 BNB is the target. The faithful run stopped at 5b on exactly this
[C F5b.0]. Do not start the day unless P4 below prints FUNDED.

## Funding -- measured at the mainnet gas price of the day (0.05 gwei)

| signer | what | gas | BNB at 0.05 gwei | at 1 gwei | at 3 gwei |
|---|---|---|---|---|---|
| deployer | phase 1 (3 tx) + phase 2 (16 tx) | 13,432,620 | 0.000672 | 0.0134 | 0.0403 |
| DMX owner | 5a (2), seeder deploy + approve + seed (3), test swap (3), poke, 11a, 11b | 2,213,827 | 0.000111 | 0.0022 | 0.0066 |
| DMX owner | BNB leg of the liquidity (5b) | -- | 2.261000 | 2.261000 | 2.261000 |
| DMX owner | test buy 0.001, half sold back 0.000458 | -- | 0.000542 net | | |

`[H2 F14.1, H2 F14.2]`. The deployer's 0.1 BNB leaves 0.099 at the day's gas
price and 0.06 even at 3 gwei. The owner's 2.35 BNB covers the leg and all
its gas even at 3 gwei; the morning's re-sizing (P4: owner >= leg + 0.002)
says SHORT only if the DMX price has risen more than about 3.8 % (a leg
above 2.348 BNB).

## Expected addresses (valid ONLY if the deployer's nonce is 0 at phase 1)

CREATE addresses follow from the deployer and its nonce, and the pair from
CREATE2 on the factory -- the fork produced exactly what mainnet will
`[H2 F1.1, H2 F2.2, H2 F2.3]`:

| nonce | contract | address |
|---|---|---|
| 0 | DaimonV2 implementation | `0xA7bC2D4D35e49bdfC8329e3673d7De520832941c` |
| 1 | DaimonV2 proxy (DMN) | `0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a` |
| 2 | DaimonMigration | `0x76368b60514b145617385847aCFF7b7EA9764725` |
| 3 | DaimonTimelock (= treasury = marketing wallet) | `0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891` |
| 4 | DaimonStaking | `0xBb596e7308D6C5AED55cEC597D372840Cbe575b1` |
| 5 | DaimonGovernor | `0x1397a7d25595B718BE6FEEDd42ed5E60F66E16De` |
| -- | DMN/WBNB pair (created by `initialize`) | `0x40A97Ae210a44057603186B4BE92BAe719342AFA` |

The LiquiditySeeder is deployed by the DMX owner: its address follows from
the owner's nonce at that moment (`cast compute-address $OWNER --nonce <n>`).
If anything lands elsewhere, stop and find out why before going on.

## Session setup (PowerShell)

```powershell
$env:PATH = "$HOME\.foundry\bin;" + $env:PATH
$RPC      = "<a BSC mainnet RPC you trust>"
$DEPLOYER = "0x4D38C9FE5250235dc99D3e098cd515B008aCa26e"   # dedicated Ledger
$OWNER    = "0xF8EC459CAEaF1052b64B38BDD67290B0c132B0Ae"   # DMX owner
$SAFE     = "0x37F45839765AD3418E29c97d5D92407Ddbf5c7a8"   # guardian, 2-of-3
$DMX      = "0x36EbA94407B53c631eE822C219e94580fadd67c7"
$DMX_POOL = "0xB24916823C61Ee6272448209174F75fAfD297B82"
$ROUTER   = "0x10ED43C718714eb63d5aA57B78B54704E256024E"   # PancakeSwap v2, verified (journal F0.4)
$FACTORY  = "0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73"
$WBNB     = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c"
$GP       = (cast gas-price --rpc-url $RPC).Trim()          # rehearsed at 50000000
$OWNER_SIGN = @("--ledger")    # or @("--account", "<keystore>") -- however the owner signs
$TX = @("--rpc-url", $RPC, "--legacy", "--gas-price", $GP) + $OWNER_SIGN
```

The fork signed with `--unlocked` (impersonation); on the day the only
difference is the signer flag. Everything else below ran as written.

## Preflight (the hour before)

| # | command | expected | if not |
|---|---|---|---|
| P1 | `cast nonce $DEPLOYER --rpc-url $RPC` | `0` | the expected addresses above no longer hold; recompute them, re-run step 1 against the new prediction |
| P2 | `cast balance $DEPLOYER --rpc-url $RPC --ether` | >= 0.1 | fund it |
| P3 | `cast wallet address --ledger` (deployer device) and the owner's signer | `$DEPLOYER` / `$OWNER` | fix the derivation path before anything else |
| P4 | `powershell -File script/fork/size-liquidity.ps1 -Rpc $RPC` | last line `FUNDED` (owner >= leg + 0.002) | fund the owner (target 2.35 BNB); do NOT start |
| P5 | `cast call $DMX "owner()(address)"`, `"getUnlockTime()(uint256)"`, `"isExcludedFromFee(address)(bool)" $OWNER`, `"_maxTxAmount()(uint256)"` (all `--rpc-url $RPC`) | `$OWNER`, `0`, `true`, `1500000000000000000000000000` | owner authority changed or a `lock()` is running: the migration could never open. Do NOT deploy |
| P6 | `git describe --tags`; `git diff audit-final -- src/`; `forge test` | `launch-config-rc1` (or its successor); empty; 203 passed | wrong checkout |
| P7 | `Test-Path deployments/two-phase-56.json`; `Test-Path broadcast/DeployPhase1.s.sol/56` | both `False` | move the old files away: phase 2 and `--resume` would read them |

**The DMX owner must NEVER call `lock()` on DMX** -- nor
`renounceOwnership` or `transferOwnership` -- until 11b is done. The real
DMX is a SafeMoon-style `Ownable`: `lock(time)` sets `owner()` to zero until
`unlock()` after the lock time, and while it runs nobody can call
`setMaxTxAmount` or `excludeFromFee`: the window could not open while the
immutable 90-day deadline keeps running.

## Step 1 -- the pair does not exist (#25) -- read-only

```powershell
$PROXY = ((cast compute-address $DEPLOYER --nonce 1) -split "\s+")[-1]
cast call $FACTORY "getPair(address,address)(address)" $PROXY $WBNB --rpc-url $RPC
```
Check: `0x0000000000000000000000000000000000000000`, and `$PROXY` is the
nonce-1 address above `[H2 F1.1]`. If a pair exists: `initialize` reuses it
(the #25 fix: `getPair` first), and the seeder opens even a pair holding
WBNB dust `[I F5b.1]` -- but someone is watching: read its `getReserves`,
then stop and decide before phase 1.

## Step 2 -- phase 1, then phase 2 -- DEPLOYER signs, nothing in between

```powershell
$env:ROUTER = $ROUTER; $env:OLD_DAIMON = $DMX; $env:GUARDIAN_ADDRESS = $SAFE
$env:MIGRATION_DURATION = "7776000"     # 90 days -- immutable from the Migration's block
Remove-Item env:MARKETING_WALLET, env:TESTNET_TREASURY_OVERRIDE, env:TREASURY_ADDRESS -ErrorAction SilentlyContinue
# 2.1 simulation (nothing sent)
forge script script/DeployPhase1.s.sol:DeployPhase1 --rpc-url $RPC --ledger --sender $DEPLOYER --legacy --with-gas-price $GP
# 2.2 broadcast
forge script script/DeployPhase1.s.sol:DeployPhase1 --rpc-url $RPC --ledger --sender $DEPLOYER --legacy --with-gas-price $GP --broadcast --slow
```
Check after 2.1 `[H2 F2.1]`: `Migration duration (days): 90`;
`Migration treasury` and `Marketing wallet` both `(= predicted timelock)`;
no `override` and no `WARNING` line.
Check after 2.2 `[H2 F2.2, H2 F2.2b]`: three transactions;
`deployments/two-phase-56.json` written; proxy, migration and predicted
Timelock == the table above; `cast nonce $DEPLOYER` == 3; and the deadline:

```powershell
$d = Get-Content deployments/two-phase-56.json -Raw | ConvertFrom-Json
cast call $d.migration "migrationDeadline()(uint256)" --rpc-url $RPC
```
== the timestamp of the Migration's deploy block + 7776000, exactly
(rehearsed: block timestamp 1790619977 -> deadline 1798395977). If 2.2 is
interrupted mid-broadcast: rerun with `--resume`. If it reverts: read the
error; nothing is claimable yet (no 11b), the only cost is gas.

```powershell
# 2.3 phase 2 -- IMMEDIATELY, no other transaction from the deployer
forge script script/DeployPhase2.s.sol:DeployPhase2 --rpc-url $RPC --ledger --sender $DEPLOYER --legacy --with-gas-price $GP --broadcast --slow
```
Check `[H2 F2.3, H2 F2.4]`: sixteen transactions; `All decentralization
asserts passed`; DaimonTimelock == `0xCdaa...0891`; fees 10/10/20; one
guardian expiry on three contracts; deployer nonce 19, about 0.00067 BNB
spent at 0.05 gwei. From here the deployer signs NOTHING. If the preflight
refuses: do NOT work around it -- abandon the phase-1 contracts and rerun
phase 1 fresh (new nonces, new addresses). If interrupted: `--resume`.

```powershell
$d = Get-Content deployments/two-phase-56.json -Raw | ConvertFrom-Json
$TOKEN = $d.token; $MIG = $d.migration; $TL = $d.timelock; $STAKING = $d.staking
$PAIR = (cast call $TOKEN "uniswapV2Pair()(address)" --rpc-url $RPC).Trim()
```

## Step 3 -- the gate, 36/36 -- read-only

```powershell
powershell -File script/verify-deploy.ps1 -Rpc $RPC
```
Check: exit code 0, `VERIFICATION PASSED: 36/36` `[H2 F3.1]`. Paste the
full output into the launch record. If anything fails: STOP. Nothing is
claimable (11b not done); the launch pauses until the failure is understood.

## Step 4 -- automation inert without reserves (#27) -- read-only

```powershell
cast call $TOKEN "swapAndLiquifyEnabled()(bool)" --rpc-url $RPC            # true
cast call $TOKEN "balanceOf(address)(uint256)" $TOKEN --rpc-url $RPC       # 0
cast call $PAIR "getReserves()(uint112,uint112,uint32)" --rpc-url $RPC      # 0 0
cast balance $TOKEN --rpc-url $RPC                                          # 0
```
`[H2 F4.1]`. A WBNB reserve here means someone griefed the pair (1 wei +
`sync()`): the router path is now refused `[I F5b.G]`, the seeder is not
affected -- go on. A material WBNB amount would be refused by the seeder's
price check; see 5b.

## Step 5a -- a non-owner is still refused; the owner claims ONLY the gross -- DMX OWNER signs

Non-owner check, launch-day form (no holder signs anything): a pure
eth_call from ANY real DMX holder `$H` (not the owner, not fee-exempt),
the allowance supplied by a state override on DMX's `_allowances`
(storage slot 7) `[H2 F5a.1b]`:

```powershell
$H = "<a real DMX holder>"
$SLOT = (cast index address $MIG (cast index address $H 7)).Trim()
cast call $MIG "claim(uint256)" 1000000000000000000000000000 --from $H --override-state-diff "${DMX}:${SLOT}:0x33b2e3c9fd0803ce8000000" --rpc-url $RPC
cast call $DMX "isExcludedFromFee(address)(bool)" $TL --rpc-url $RPC        # false
```
Check: the claim reverts with `AmountMismatch` (selector `0x55e97b0d`); the
Timelock is not exempt. Use `--override-state-diff`, NOT `--override-state`:
the latter replaces DMX's whole storage and the call dies in `SafeMath:
division by zero` before reaching the check (journal, run F).

```powershell
powershell -File script/fork/size-liquidity.ps1 -Rpc $RPC -Token $TOKEN
$GROSS  = "<GROSS from the output>"      # rehearsed 4998406600825315109208480483
$BNB    = "<BNB_LEG from the output>"    # rehearsed 2261000000000000000
cast send $DMX "approve(address,uint256)" $MIG $GROSS @TX
cast send $MIG "claim(uint256)" $GROSS @TX
```
Check `[H2 F5a.5]`: `migratedAmount($OWNER)` == GROSS; the owner's DMN ==
GROSS; `DMX.balanceOf($TL)` == GROSS -- 1:1 on every leg. The owner can
claim before 11b only because it is fee- and cap-exempt on DMX
`[H2 F5a.2]`. If the helper does not print FUNDED: STOP before the claim.
If the claim reverts with `AmountMismatch`: the owner lost its DMX
exemption -- STOP.

## Step 5b (with step 6 merged) -- the LiquiditySeeder -- DMX OWNER signs

```powershell
# 5b.1 deploy the seeder (constructor: owner, DMN, pair, WBNB, Timelock)
forge create script/launch/LiquiditySeeder.sol:LiquiditySeeder @TX --broadcast --constructor-args $OWNER $TOKEN $PAIR $WBNB $TL
$SEEDER = "<Deployed to: from the output>"
cast call $SEEDER "owner()(address)" --rpc-url $RPC        # $OWNER   (and dmn, pair, wbnb, timelock: the launch addresses)
cast call $SEEDER "used()(bool)" --rpc-url $RPC            # false
# 5b.2 approve EXACTLY the gross, then seed with the BNB leg
cast send $TOKEN "approve(address,uint256)" $SEEDER $GROSS @TX
cast send $SEEDER "seed(uint256)" $GROSS --value $BNB @TX
```
The constructor refuses a pair that is not the token's own DMN/WBNB pair
and a codeless Timelock `[H2 F5b.S1]`. `seed` is owner-only and single-use;
in ONE transaction it moves the gross DMN owner -> pair, wraps the BNB and
sends it, calls `pair.mint(TIMELOCK)`, and then refuses to finish unless:
the pool price is within 0.10 % of msg.value / DMN-received; every LP token
is the Timelock's (`totalSupply - 1000`); nothing -- BNB, WBNB, DMN, LP --
is left in the seeder; the owner's approval was exact (0 left).

Check `[H2 F5b.1, H2 F6.1, H2 F6.2]`:
- `getReserves` of `$PAIR`: DMN == NET from the helper (exact), WBNB == `$BNB`
  (+ any dust a griefer left: `[I F5b.1]` shows `+1 wei`);
- opening price `WBNB x 1e18 / DMN` == the DMX price within 1 ppm
  (rehearsed: 471191825 clean, 471191826 griefed, DMX 471191826);
- the seed transaction's receipt holds exactly ONE LP `Transfer(0x0 ->
  $TL)`, equal to `pair.balanceOf($TL)` == `totalSupply() - 1000`;
  `pair.balanceOf($OWNER)` == 0, `pair.balanceOf($DEPLOYER)` == 0 -- this
  is step 6, done; publish the seed transaction hash;
- `used()` == true; the seeder holds 0 BNB, 0 WBNB, 0 DMN, 0 LP;
  `allowance($OWNER, $SEEDER)` == 0; the owner's DMN == 0.

If `seed` reverts with `PriceOutOfTolerance`: someone parked a material
amount in the pair -- STOP and decide (a donation of that size moves the
opening price; the seeder refuses it on purpose; unit test
`test_SkewingWbnbDonationBeyondToleranceReverts`). `ApprovalNotExact`:
re-approve exactly `$GROSS`. `NotOwner` / `AlreadyUsed`: wrong signer / the
pool is already open -- read the pair before anything else.

## Step 7 -- one pool only -- read-only

```powershell
cast call $FACTORY "getPair(address,address)(address)" $TOKEN $WBNB --rpc-url $RPC   # == $PAIR
cast call $FACTORY "getPair(address,address)(address)" $TOKEN 0x55d398326f99059fF775485246999027B3197955 --rpc-url $RPC  # USDT: 0x0
cast call $FACTORY "getPair(address,address)(address)" $TOKEN 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56 --rpc-url $RPC  # BUSD: 0x0
```
`[H2 F7.1]`

## Step 8 -- reserves non-zero, automation live -- read-only

`getReserves` both > 0; the token's own DMN balance (the fee inventory) ==
about 3 % of GROSS = 0.15 B `[H2 F8.1]` -- below the 0.2 B conversion
threshold, see step 10.

## Step 9 -- the test swap, fee exactly 4 % -- DMX OWNER signs

The owner holds no DMN after 5b, so the test sell needs a small buy first:

```powershell
$DEADLINE = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 1200
cast send $ROUTER "swapExactETHForTokensSupportingFeeOnTransferTokens(uint256,address[],address,uint256)" 0 "[$WBNB,$TOKEN]" $OWNER $DEADLINE --value 1000000000000000 @TX
$GOT = (cast call $TOKEN "balanceOf(address)(uint256)" $OWNER --rpc-url $RPC).Split(" ")[0]
$SELL = ([System.Numerics.BigInteger]::Parse($GOT) / 2).ToString()
$P0 = (cast call $TOKEN "balanceOf(address)(uint256)" $PAIR --rpc-url $RPC).Split(" ")[0]
cast send $TOKEN "approve(address,uint256)" $ROUTER $SELL @TX
cast send $ROUTER "swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)" $SELL 0 "[$TOKEN,$WBNB]" $OWNER $DEADLINE @TX
```
Check `[H2 F9.2]`: the pair's DMN `balanceOf` rose by EXACTLY
`SELL - floor(SELL x 10 / 1000) - floor(SELL x 30 / 1000)` (96 %, up to the
two floors: it can be 1-2 wei above `floor(SELL x 96 / 100)`); 95 % would
mean the historical 5 % fee. `cast balance $TOKEN` == 0 and `cast balance
$TL` == 0 (a router sell converts nothing, #1). Measure the pair by
`balanceOf`, not reserves.

## Step 10 -- the first poke -- DMX OWNER signs

```powershell
cast send $TOKEN "transfer(address,uint256)" $PAIR 1 @TX
```
**Expected: the poke converts NOTHING.** The fee inventory is ~0.15 B (3 %
of the 5b transfer), below the 0.2 B threshold `[H2 F10.1]`: `cast balance
$TL` == 0, `cast balance $STAKING` unchanged, the inventory unchanged. That
is the correct launch-day result, not a failure. The first conversion comes
later, once about 1.66 B of further taxed volume has armed it: one 0.2 B
chunk sells, 20/30 of the BNB to staking, 10/30 kept for buyback, ZERO to
the Timelock, price about -7.8 % on the launch pool `[H2 F10.2, H2 F10.3]`.
A Timelock BNB balance above 0 at share 1000 is a stop-everything signal.

## Step 11a, then 11b -- the window opens -- DMX OWNER signs, back to back

```powershell
cast send $DMX "setMaxTxAmount(uint256)" 1000000000000000000000000000000 @TX   # 11a
cast send $DMX "excludeFromFee(address)" $TL @TX                               # 11b, LAST
```
Check `[H2 F11a, H2 F11b]`:
- `cast call $DMX "_maxTxAmount()(uint256)"` == `1000000000000000000000000000000`;
- `cast call $DMX "isExcludedFromFee(address)(bool)" $TL` == true, and `$MIG` == false.

**Neither call emits an event on the real DMX** `[H2 F11.x]` (the mock
emitted one on 11a): record both hashes by hand; nothing that watches logs
will see them. If 11a mines and 11b fails: resend 11b -- the raised cap
alone opens nothing (claims still revert with `AmountMismatch`). If 11b
lands first by mistake: send 11a at once -- until then any claim above
1.5 B reverts with the DMX cap message `[H2 F11.0]`. Never use DMX's
`presale(true)`: it lifts the fee and the cap for everyone.

## After 11b -- the first claims

Real holders claim 1:1 through the open window: a real holder above the
old cap claimed 10.00 B exactly on every leg, a real holder below it
1.00 B `[H2 F12.1, H2 F12.2]`. For each `Claimed` event, check the
treasury's DMX delta in THAT transaction == the amount.

**The Timelock's DMX grows above `totalMigrated`.** The real DMX is a
reflection token and the Timelock is not reward-excluded on it: every taxed
DMX transfer anywhere credits it a share (+6,399 DMX from one 0.01 B
transfer between two other holders) `[H2 F12.4]`. Never expect
`DMX.balanceOf(TL) == totalMigrated`; expect `>=`. The custody rule
(CHECKLIST_MAINNET.md, Zenith #6) covers those DMX too.

## Verification -- after the day

```powershell
powershell -File script/launch/verify-sourcify.ps1 -Chain 56 -Rpc $RPC -Seeder $SEEDER -SeederTx <the seeder's deploy tx>
```
It reads every address, constructor argument and creation transaction from
the phase journals (the seeder's from its own getters), submits each
contract to **Sourcify**'s v2 API, polls the job, reads the verdict back,
and exits with the number of contracts not verified. Rehearsed on the
Chapel 2b deployment: **7/7 exact_match** (implementation, proxy,
Migration, Timelock, Staking, Governor, the mock DMX). Do NOT use `forge
verify-contract --verifier sourcify`: with forge 1.5.1 it printed "already
verified" and verified nothing.

**BscScan** has no free API for BNB Chain, so the explorer's own form is
the path. The script also writes, per contract, into
`script/launch/out/verify-56/`:
`<Name>.standard-input.json` and `<Name>.constructor-args.txt`. On
bscscan.com, for each address: Contract -> Verify and Publish -> Compiler
Type **Solidity (Standard-Json-Input)**, compiler **v0.8.26+commit.8a97fa7a**,
license MIT -> upload the `.standard-input.json` -> paste the
`.constructor-args.txt` content (no `0x`; empty for the implementation) ->
pick the contract name -> complete the human check -> submit. For the proxy
afterwards: More Options -> "Is this a proxy?" -> Verify, to link the
implementation's ABI. (Sourcify also forwarded each Chapel submission to
Etherscan's API on its own; whether that landed on BscScan could not be
checked from here -- look at the explorer page first, the form may already
be unnecessary.)

## The real DMX vs the mock -- every difference observed

1. Getter names: `isExcludedFromFee(address)` and `_maxTxAmount()` (the
   mock: `excludedFromFee`, `maxTxAmount`). Any tool written against the
   mock breaks on the real token.
2. Ownership is `Ownable` with `transferOwnership`, `renounceOwnership`
   and the SafeMoon `lock(time)` / `unlock()` pair (the mock: an immutable
   owner). Hence the rule above: the owner never calls `lock()`.
3. Non-owner calls revert with `Ownable: caller is not the owner` (the
   mock: `DMX: only owner`).
4. No event on `setMaxTxAmount` (the mock emits `MaxTxAmountUpdated`) nor
   on `excludeFromFee`.
5. Reflection: 4 % is redistributed to holders, 7 % goes to the contract
   (2 % buyback + 5 % marketing) -- the same 11 % total as the mock, which
   burns it. Consequence: the treasury's DMX grows between claims.
6. `transferFrom` moves the tokens before checking the allowance (same
   outcome, different revert text: `ERC20: transfer amount exceeds
   allowance`); a zero-amount transfer reverts (the migration already
   refuses zero).
7. Transfers TO the DMX pool trigger DMX's own swap and buyback (the DMX
   contract holds 20.14 B DMX and 4.26 BNB); nothing on the claim path
   touches it.
8. Holders: one real holder's account carries an EIP-7702 delegation; its
   claim behaved exactly like a plain EOA's.

## What the fork could not rehearse

Signing devices (impersonation stood in for the Ledger and the owner's
signer); BscScan's web form (Sourcify was rehearsed on Chapel instead); the
public mempool against a real adversary (the grief was rehearsed, mined, by
an impersonated stranger); real time between steps (the fork mined each
transaction instantly: 11a and 11b one block apart); the monitor watching;
the migration deadline itself.
