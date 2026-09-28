# Launch day -- the script

Every command of the Daimon DAO mainnet launch, in order: who signs it,
what to check after it, and what to do when a check fails. Written from
what ran on a local fork of BSC mainnet against the REAL DMX, the REAL DMX
pool and the REAL PancakeSwap v2 router (docs/MAINNET_FORK_RESULTS.md,
2026-09-28, runs C and G), not from memory. The launch order is the one in
CHECKLIST_MAINNET.md (master, 08eb17e); the code is the tag
`launch-config-rc1`.

Run references in brackets -- `[G F5b.1]` -- point at the journal row that
proves the step.

## 0. Blockers found by the rehearsal -- resolve BEFORE the day

1. **The DMX owner cannot fund step 5b.** It holds 0.096153 BNB (mainnet,
   2026-09-28). Step 5b needs the BNB leg -- 4.8 B DMN x the DMX price --
   = **2.261 BNB** at that day's DMX pool price (4.71191826e-10 BNB per
   token), plus about 0.002 BNB of gas margin: **short by 2.1668 BNB**
   `[C F5a.4, C F5b.0]`. The faithful run stopped there. Fund the owner
   with at least the shortfall, plus a margin for the DMX price moving
   (the leg scales linearly with it: +10 % price = +0.226 BNB). Suggested
   owner balance on the morning: **>= 2.5 BNB**. Re-check with the sizing
   helper (P4 below); if it does not print FUNDED, do not start.
2. **`MIGRATION_DURATION` is not decided anywhere.** Unset, phase 1 uses
   30 days `[G F2.1]`, and the deadline is immutable from phase 1. Decide
   it and set it (in seconds, 30-365 days).
3. **Step 5b can be griefed for a few cents** `[G F5b.P1]`: between phase 1
   (the pair is created) and 5b, anyone can send 1 wei of WBNB to the
   empty DMN pair and call `sync()`; `addLiquidityETH` then reverts with
   `PancakeLibrary: INSUFFICIENT_LIQUIDITY`. The direct path (transfer both
   legs + `pair.mint`) still opens the pool at the right price
   `[G F5b.P2]`, but as separate transactions it leaves the owner's DMN and
   WBNB in the pair above its reserves until `mint`, where anyone can take
   them with `skim()`. The fallback is safe only if the four calls land
   atomically (a bundle through a private/MEV-protected submission, or a
   one-shot contract). Prepare that path in advance; keep the time between
   phase 1 and 5b as short as the gate allows.
4. **BscScan verification was not rehearsed** (`ETHERSCAN_API_KEY` is empty
   in the local `.env`). Verify after the day (DEPLOY.md §6) or set the key
   and add `--verify` to both phases.

## Funding -- measured, at the mainnet gas price of the day (0.05 gwei)

| signer | what | gas | BNB at 0.05 gwei | at 1 gwei | at 3 gwei |
|---|---|---|---|---|---|
| deployer | phase 1 (3 tx) + phase 2 (16 tx) | 13,432,620 | 0.000672 | 0.0134 | 0.0403 |
| DMX owner | 5a, 5b, 6, 9, 10, 11a, 11b (11 tx) | 1,464,763 | 0.000073 | 0.0015 | 0.0044 |
| DMX owner | BNB leg of the liquidity (5b) | -- | 2.261000 | 2.261000 | 2.261000 |
| DMX owner | test buy 0.001, half sold back 0.000458 | -- | 0.000542 net | | |

`[G F14.1, G F14.2]`. The deployer's planned **0.2 BNB is enough** (spent
0.000672; 3 gwei would still leave 0.16). The owner needs **the leg + ~0.002**.

## Expected addresses (valid ONLY if the deployer's nonce is 0 at phase 1)

CREATE addresses follow from the deployer and its nonce, and the pair from
CREATE2 on the factory -- the fork produced exactly what mainnet will
`[G F1.1, G F2.2, G F2.3]`:

| nonce | contract | address |
|---|---|---|
| 0 | DaimonV2 implementation | `0xA7bC2D4D35e49bdfC8329e3673d7De520832941c` |
| 1 | DaimonV2 proxy (DMN) | `0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a` |
| 2 | DaimonMigration | `0x76368b60514b145617385847aCFF7b7EA9764725` |
| 3 | DaimonTimelock (= treasury = marketing wallet) | `0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891` |
| 4 | DaimonStaking | `0xBb596e7308D6C5AED55cEC597D372840Cbe575b1` |
| 5 | DaimonGovernor | `0x1397a7d25595B718BE6FEEDd42ed5E60F66E16De` |
| -- | DMN/WBNB pair (created by `initialize`) | `0x40A97Ae210a44057603186B4BE92BAe719342AFA` |

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
| P2 | `cast balance $DEPLOYER --rpc-url $RPC --ether` | >= 0.2 | fund it |
| P3 | `cast wallet address --ledger` (deployer device) and the owner's signer | `$DEPLOYER` / `$OWNER` | fix the derivation path before anything else |
| P4 | `powershell -File script/fork/size-liquidity.ps1 -Rpc $RPC` | last line `FUNDED` | fund the owner (blocker 1); do NOT start |
| P5 | `cast call $DMX "owner()(address)"`, `"getUnlockTime()(uint256)"`, `"isExcludedFromFee(address)(bool)" $OWNER`, `"_maxTxAmount()(uint256)"` (all `--rpc-url $RPC`) | `$OWNER`, `0`, `true`, `1500000000000000000000000000` | owner authority changed: the migration can never open. Do NOT deploy |
| P6 | `git describe --tags`; `git diff audit-final -- src/` | `launch-config-rc1`; empty | wrong checkout |
| P7 | `Test-Path deployments/two-phase-56.json`; `Test-Path broadcast/DeployPhase1.s.sol/56` | both `False` | move the old files away: phase 2 and `--resume` would read them |
| P8 | `$env:MIGRATION_DURATION` | the decided value, in seconds | blocker 2 |

## Step 1 -- the pair does not exist (#25) -- read-only

```powershell
$PROXY = ((cast compute-address $DEPLOYER --nonce 1) -split "\s+")[-1]
cast call $FACTORY "getPair(address,address)(address)" $PROXY $WBNB --rpc-url $RPC
```
Check: `0x0000000000000000000000000000000000000000`, and `$PROXY` is the
nonce-1 address above `[G F1.1]`. If a pair exists: `initialize` reuses
it (the #25 fix: `getPair` first), but someone is watching, and a
pre-created pair can already carry the WBNB dust of blocker 3 -- read its
`getReserves`, then stop and decide before phase 1.

## Step 2 -- phase 1, then phase 2 -- DEPLOYER signs, nothing in between

```powershell
$env:ROUTER = $ROUTER; $env:OLD_DAIMON = $DMX; $env:GUARDIAN_ADDRESS = $SAFE
Remove-Item env:MARKETING_WALLET, env:TESTNET_TREASURY_OVERRIDE, env:TREASURY_ADDRESS -ErrorAction SilentlyContinue
# 2.1 simulation (nothing sent)
forge script script/DeployPhase1.s.sol:DeployPhase1 --rpc-url $RPC --ledger --sender $DEPLOYER --legacy --with-gas-price $GP
# 2.2 broadcast
forge script script/DeployPhase1.s.sol:DeployPhase1 --rpc-url $RPC --ledger --sender $DEPLOYER --legacy --with-gas-price $GP --broadcast --slow
```
Check after 2.1: `Migration treasury` and `Marketing wallet` both say
`(= predicted timelock)`; no `override` and no `WARNING` line;
`Migration duration (days):` is the decided value `[G F2.1]`.
Check after 2.2: three transactions; `deployments/two-phase-56.json`
written; proxy, migration and predicted Timelock == the table above;
`cast nonce $DEPLOYER` == 3 `[G F2.2]`.
If 2.2 is interrupted mid-broadcast: rerun with `--resume`. If it reverts:
read the error; nothing is claimable yet (no 11b), the only cost is gas.

```powershell
# 2.3 phase 2 -- IMMEDIATELY, no other transaction from the deployer
forge script script/DeployPhase2.s.sol:DeployPhase2 --rpc-url $RPC --ledger --sender $DEPLOYER --legacy --with-gas-price $GP --broadcast --slow
```
Check: sixteen transactions; `All decentralization asserts passed`;
DaimonTimelock == `0xCdaa...0891`; fees 10/10/20; one guardian expiry on
three contracts; deployer nonce 19; deployer spent about 0.00067 BNB at
0.05 gwei `[G F2.3, G F2.4]`. From here the deployer signs NOTHING.
If the preflight refuses: do NOT work around it -- abandon the phase-1
contracts and rerun phase 1 fresh (new nonces, new addresses). If it is
interrupted mid-broadcast: `--resume`.

```powershell
$d = Get-Content deployments/two-phase-56.json -Raw | ConvertFrom-Json
$TOKEN = $d.token; $MIG = $d.migration; $TL = $d.timelock; $STAKING = $d.staking
$PAIR = (cast call $TOKEN "uniswapV2Pair()(address)" --rpc-url $RPC).Trim()
```

## Step 3 -- the gate, 36/36 -- read-only

```powershell
powershell -File script/verify-deploy.ps1 -Rpc $RPC
```
Check: exit code 0, `VERIFICATION PASSED: 36/36` `[G F3.1]`. Paste the
full output into the launch record. If anything fails: STOP. Nothing is
claimable (11b not done); the launch pauses here until the failure is
understood.

## Step 4 -- automation inert without reserves (#27) -- read-only

```powershell
cast call $TOKEN "swapAndLiquifyEnabled()(bool)" --rpc-url $RPC            # true
cast call $TOKEN "balanceOf(address)(uint256)" $TOKEN --rpc-url $RPC       # 0
cast call $PAIR "getReserves()(uint112,uint112,uint32)" --rpc-url $RPC      # 0 0
cast balance $TOKEN --rpc-url $RPC                                          # 0
```
`[G F4.1]`. If the pair shows a WBNB reserve: the grief of blocker 3
happened -- 5b will need the atomic fallback.

## Step 5a -- a non-owner is still refused; the owner claims ONLY the gross -- DMX OWNER signs

Non-owner check, launch-day form (no holder signs anything): a pure
eth_call from ANY real DMX holder `$H` (not the owner, not fee-exempt),
the allowance supplied by a state override on DMX's `_allowances`
(storage slot 7) `[G F5a.1b]`:

```powershell
$H = "<a real DMX holder>"
$SLOT = (cast index address $MIG (cast index address $H 7)).Trim()
cast call $MIG "claim(uint256)" 1000000000000000000000000000 --from $H --override-state-diff "${DMX}:${SLOT}:0x33b2e3c9fd0803ce8000000" --rpc-url $RPC
cast call $DMX "isExcludedFromFee(address)(bool)" $TL --rpc-url $RPC        # false
```
Check: the claim reverts with `AmountMismatch` (selector `0x55e97b0d`);
the Timelock is not exempt. Use `--override-state-diff`, NOT
`--override-state`: the latter replaces DMX's whole storage and the call
dies in `SafeMath: division by zero` before reaching the check (journal,
run F). The mined equivalent (approve + claim by a real holder) was
refused the same way `[G F5a.1]`.

```powershell
powershell -File script/fork/size-liquidity.ps1 -Rpc $RPC -Token $TOKEN
$GROSS  = "<GROSS from the output>"      # rehearsed 4998406600825315109208480483
$BNB    = "<BNB_LEG from the output>"    # rehearsed 2261000000000000000
cast send $DMX "approve(address,uint256)" $MIG $GROSS @TX
cast send $MIG "claim(uint256)" $GROSS @TX
```
Check: `cast call $MIG "migratedAmount(address)(uint256)" $OWNER` == GROSS;
`cast call $TOKEN "balanceOf(address)(uint256)" $OWNER` == GROSS;
`cast call $DMX "balanceOf(address)(uint256)" $TL` == GROSS -- 1:1 exact
on every leg `[G F5a.5]`. The owner can claim before 11b only because it is
fee- and cap-exempt on DMX `[G F5a.2]`. If the helper does not print
FUNDED: STOP before the claim. If the claim reverts with `AmountMismatch`:
the owner lost its DMX exemption -- STOP.

## Step 5b -- initial liquidity -- DMX OWNER signs

```powershell
$DEADLINE = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 1200
cast send $TOKEN "approve(address,uint256)" $ROUTER $GROSS @TX
cast send $ROUTER "addLiquidityETH(address,uint256,uint256,uint256,address,uint256)" $TOKEN $GROSS $GROSS $BNB $OWNER $DEADLINE --value $BNB @TX
```
The minimums equal the amounts: on an empty pair the router uses exactly
what it is given, and on a pair that is not empty the call refuses instead
of mispricing. Check `[G F5b.1]`:
- `getReserves` of `$PAIR`: DMN == NET from the helper (exact), WBNB == `$BNB`;
- opening price `WBNB x 1e18 / DMN` <= the DMX price, within 1 ppm
  (rehearsed: 471191825 vs 471191826 wei per token);
- the owner's DMN == 0; the owner holds the LP.

If it reverts with `PancakeLibrary: INSUFFICIENT_LIQUIDITY`: the pair was
griefed (blocker 3). Read `getReserves`: if the WBNB reserve is dust, open
the pool through the ATOMIC fallback -- the same four calls the fork ran
`[G F5b.P2]`: `TOKEN.transfer(PAIR, GROSS)`, `WBNB.deposit{value: BNB}`,
`WBNB.transfer(PAIR, BNB)`, `PAIR.mint(OWNER)` -- in one bundle, never as
four public transactions (`skim()` would take the legs in between). If the
donation is material, STOP and decide: it would move the opening price.

## Step 6 -- every LP token to the Timelock -- DMX OWNER signs

```powershell
$LP = (cast call $PAIR "balanceOf(address)(uint256)" $OWNER --rpc-url $RPC).Split(" ")[0]
cast send $PAIR "transfer(address,uint256)" $TL $LP @TX
```
Check `[G F6.1]`: `balanceOf(OWNER)` == 0, `balanceOf(DEPLOYER)` == 0,
`balanceOf(TL)` == `totalSupply()` - 1000. Publish the transaction hash.

## Step 7 -- one pool only -- read-only

```powershell
cast call $FACTORY "getPair(address,address)(address)" $TOKEN $WBNB --rpc-url $RPC   # == $PAIR
cast call $FACTORY "getPair(address,address)(address)" $TOKEN 0x55d398326f99059fF775485246999027B3197955 --rpc-url $RPC  # USDT: 0x0
cast call $FACTORY "getPair(address,address)(address)" $TOKEN 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56 --rpc-url $RPC  # BUSD: 0x0
```
`[G F7.1]`

## Step 8 -- reserves non-zero, automation live -- read-only

`getReserves` both > 0; `balanceOf(TOKEN)` on the token (the fee inventory)
== about 3 % of GROSS = 0.15 B `[G F8.1]` -- below the 0.2 B conversion
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
Check `[G F9.2]`: the pair's DMN `balanceOf` rose by EXACTLY
`SELL - floor(SELL x 10 / 1000) - floor(SELL x 30 / 1000)` (96 %, up to the
two floors: the token floors each fee separately, so it can be 1-2 wei
above `floor(SELL x 96 / 100)`); a 95 % result would mean the historical
5 % fee. `cast balance $TOKEN` == 0 and `cast balance $TL` == 0 (a router
sell converts nothing, #1). Measure the pair by `balanceOf`, not reserves.

## Step 10 -- the first poke -- DMX OWNER signs

```powershell
cast send $TOKEN "transfer(address,uint256)" $PAIR 1 @TX
```
Expected on launch day: **nothing converts** -- the inventory is ~0.15 B,
under the 0.2 B threshold `[G F10.1]`; `cast balance $TL` == 0,
`cast balance $STAKING` unchanged. The first real conversion needs about
1.66 B of further taxed volume. When it comes (any poke after that): one
0.2 B chunk sells, 20/30 of the BNB to staking, 10/30 kept for buyback,
ZERO to the Timelock; on the launch pool the price moves about -7.8 %
`[G F10.2, G F10.3]`. A Timelock BNB balance above 0 at share 1000 is a
stop-everything signal.

## Step 11a, then 11b -- the window opens -- DMX OWNER signs, back to back

```powershell
cast send $DMX "setMaxTxAmount(uint256)" 1000000000000000000000000000000 @TX   # 11a
cast send $DMX "excludeFromFee(address)" $TL @TX                               # 11b, LAST
```
Check `[G F11a, G F11b]`:
- `cast call $DMX "_maxTxAmount()(uint256)"` == `1000000000000000000000000000000`;
- `cast call $DMX "isExcludedFromFee(address)(bool)" $TL` == true, and `$MIG` == false.

**Neither call emits an event** on the real DMX `[G F11.x]` (the mock
emitted one on 11a): record both hashes by hand; nothing that watches logs
will see them. If 11a mines and 11b fails: resend 11b -- the raised cap
alone opens nothing (claims still revert with `AmountMismatch`). If 11b
lands first by mistake: send 11a at once -- until then any claim above
1.5 B reverts with the DMX cap message `[G F11.0]`. Never use DMX's
`presale(true)`: it lifts the fee and the cap for everyone.

## After 11b -- the first claims

Real holders claim 1:1 through the open window: a real holder above the
old cap claimed 10.00 B exactly on every leg, a real holder below it
1.00 B `[G F12.1, G F12.2]`. For each `Claimed` event, check the
treasury's DMX delta in THAT transaction == the amount. Do not expect
`DMX.balanceOf(TL) == totalMigrated` over time: the Timelock is not
reward-excluded on DMX, and every taxed DMX transfer anywhere credits it a
reflection share (+6,399 DMX from one 0.01 B transfer) `[G F12.4]`. The
custody rule (CHECKLIST_MAINNET.md, Zenith #6) covers those DMX too.

## The real DMX vs the mock -- every difference observed

1. Getter names: `isExcludedFromFee(address)` and `_maxTxAmount()` (the
   mock: `excludedFromFee`, `maxTxAmount`). Any tool written against the
   mock breaks on the real token.
2. Ownership is `Ownable` with `transferOwnership`, `renounceOwnership`
   and the SafeMoon `lock(time)` / `unlock()` pair (the mock: an immutable
   owner). A `lock` makes `owner()` read zero until `unlock`; checked by P5
   (`getUnlockTime` 0 on 2026-09-28).
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
signer); BscScan verification; the public mempool (front-running, the
grief of blocker 3 by a real adversary, the `skim()` race); real time
between steps (the fork mined each transaction instantly: 11a and 11b one
block apart); the monitor watching; the migration deadline itself.
