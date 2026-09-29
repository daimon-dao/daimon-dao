# Launch day -- the script

Status: RUN on 2026-09-29 -- steps 1-8 and 11a/11b done, 9 and 10 skipped
by decision; the migration window opened at 11b (2026-09-29 20:06:24 UTC)
and closes 2026-12-28 01:08:44 UTC. What actually ran, with every hash and
every deviation from this script, is docs/MAINNET_LAUNCH_RECORD.md.

Every command of the Daimon DAO mainnet launch, in order: who signs it,
what to check after it, and what to do when a check fails. Written from
what ran on a local fork of BSC mainnet against the REAL DMX, the REAL DMX
pool and the REAL PancakeSwap v2 router (docs/MAINNET_FORK_RESULTS.md,
2026-09-28), not from memory. The launch order is the one in
CHECKLIST_MAINNET.md, with two changes decided on 2026-09-29 and in force
here: the deployer (not the owner) deploys the LiquiditySeeder, and every
contract is verified BEFORE the first owner step (steps 4b, 4c); the
protocol code is the tag `launch-config-rc2`
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
| Verification | Sourcify via `script/launch/verify-sourcify.ps1` + BscScan manual web form, **before any owner step** (step 4c) | Chapel 2b: 7/7 exact_match |
| Signers | **deployer**: Ledger at `$DPATH` = `m/44'/60'/9'/0/0`, through forge (`--ledger` + the path), P3 re-checked before every broadcast -- phase 1, phase 2 and the LiquiditySeeder deploy (step 4b). **DMX owner**: MetaMask (software wallet), through bscscan.com "Write Contract" -- every owner step, no forge, no cast | decided 2026-09-29 |

**The owner's balance.** 2.35 BNB is the target; P4 below must print
FUNDED (the faithful run stopped at 5b on a short owner [C F5b.0]). Read on
2026-09-29 at block 124610450: 2.384999 BNB, leg 1.994 BNB, FUNDED.

## Funding -- measured at the mainnet gas price of the day (0.05 gwei)

| signer | what | gas | BNB at 0.05 gwei | at 1 gwei | at 3 gwei |
|---|---|---|---|---|---|
| deployer | phase 1 (3 tx) + phase 2 (16 tx) | 13,432,620 | 0.000672 | 0.0134 | 0.0403 |
| deployer | LiquiditySeeder deploy (step 4b, 1 tx) | 755,546 | 0.000038 | 0.0008 | 0.0023 |
| DMX owner | 5a (2), approve + seed (2), test swap (3), poke, 11a, 11b | 1,458,281 | 0.000073 | 0.0015 | 0.0044 |
| DMX owner | BNB leg of the liquidity (5b) | -- | 2.261000 | 2.261000 | 2.261000 |
| DMX owner | test buy 0.001, half sold back 0.000458 | -- | 0.000542 net | | |

`[H2 F14.1, H2 F14.2]`; the seeder deploy's 755,546 gas moved from the
owner's row to the deployer's (the fork deployed it from the owner
`[H2 F5b.S1]`). MetaMask may price the owner's gas above the day's 0.05
gwei; the rows at 1 and 3 gwei show that it does not matter. The deployer's 0.1 BNB leaves 0.099 at the day's gas
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
| 19 | LiquiditySeeder (step 4b, the deployer's first transaction after phase 2) | `0x21ab79825b86137CF1b04884FCFC4e4b717ce062` |

If anything lands elsewhere, stop and find out why before going on.

## Session setup (PowerShell)

```powershell
$env:PATH = "$HOME\.foundry\bin;" + $env:PATH
$RPC      = "<a BSC mainnet RPC you trust>"
$DEPLOYER = "0x4D38C9FE5250235dc99D3e098cd515B008aCa26e"   # dedicated Ledger
$DPATH    = "m/44'/60'/9'/0/0"   # the deployer on the Ledger: Ledger Live scheme, account index 9 (index 0 is ANOTHER account)
$OWNER    = "0xF8EC459CAEaF1052b64B38BDD67290B0c132B0Ae"   # DMX owner
$SAFE     = "0x37F45839765AD3418E29c97d5D92407Ddbf5c7a8"   # guardian, 2-of-3
$DMX      = "0x36EbA94407B53c631eE822C219e94580fadd67c7"
$DMX_POOL = "0xB24916823C61Ee6272448209174F75fAfD297B82"
$ROUTER   = "0x10ED43C718714eb63d5aA57B78B54704E256024E"   # PancakeSwap v2, verified (journal F0.4)
$FACTORY  = "0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73"
$WBNB     = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c"
$GP       = (cast gas-price --rpc-url $RPC).Trim()          # rehearsed at 50000000

# P3 as a hard gate: the Ledger must return $DEPLOYER at $DPATH, or nothing is sent.
function Assert-Deployer {
  $a = ((cast wallet address --ledger --mnemonic-derivation-path $DPATH 2>&1 | Select-Object -Last 1) | Out-String).Trim()
  if ($a -ne $DEPLOYER) { throw "STOP (P3): the Ledger returns '$a' at $DPATH, not $DEPLOYER -- nothing was sent" }
  Write-Output "P3 OK: $a at $DPATH"
}
```

**The deployer's derivation path.** A plain `--ledger` uses
`m/44'/60'/0'/0/0`, which on this device is ANOTHER, everyday account
(`0x9Fc0...848d`, nonce 122 on 2026-09-29). The deployer is at
`$DPATH` = `m/44'/60'/9'/0/0` (Ledger Live scheme, account index 9; the
guardian signer F1 `0xD9dB...fc16` is on the same device at
`m/44'/60'/3'/0/0`), found on 2026-09-29 by deriving indices 0-25 in the
Ledger Live, legacy and BIP44 schemes. Every deployer command carries the
path, and the flag differs by tool:

| tool | path flag | signer guard |
|---|---|---|
| `forge script` (2.1, 2.2, 2.3, any `--resume`) | `--mnemonic-derivation-paths $DPATH` (plural) | `--sender $DEPLOYER`: forge will not broadcast for a sender none of its wallets controls |
| `forge create` (4b) | `--mnemonic-derivation-path $DPATH` (singular) | `--from $DEPLOYER` (forge create has no `--sender`); the proof is the address: CREATE from `$DEPLOYER` at nonce 19 lands on `0x21ab...e062` |
| `cast wallet address` (P3) | `--mnemonic-derivation-path $DPATH` (singular) | -- |

Every deployer **broadcast** is written as ONE line that starts with
`Assert-Deployer;`. Keep it one line: when a line is pasted into
PowerShell and the gate throws, the rest of THAT line is skipped, but a
separate line pasted with it would still run.

The fork signed with `--unlocked` (impersonation). On the day the
deployer's commands are the fork's with `--ledger` and `$DPATH`; the owner's
transactions are the same calls, with the same arguments, sent from
MetaMask through BscScan (see "How the owner signs" below). Neither
signing path ran on the fork.

`MIGRATION_DURATION=7776000` is also set in the local `.env` (forge loads
it), so phase 1 does not depend on the shell variable of step 2. `.env`
must NOT set `MARKETING_WALLET`, `TREASURY_ADDRESS` or
`TESTNET_TREASURY_OVERRIDE` to a value (empty is fine).

## Preflight (the hour before)

| # | command | expected | if not |
|---|---|---|---|
| P1 | `cast nonce $DEPLOYER --rpc-url $RPC` | `0` | the expected addresses above no longer hold; recompute them, re-run step 1 against the new prediction |
| P2 | `cast balance $DEPLOYER --rpc-url $RPC --ether` | >= 0.1 | fund it |
| P3 | `Assert-Deployer` (= `cast wallet address --ledger --mnemonic-derivation-path $DPATH`; deployer device unlocked, Ledger Live closed, Ethereum app open, "Blind signing" enabled in its settings: every deploy carries contract data) and, in MetaMask, the selected account on network "BNB Smart Chain" (chain ID 56) | `P3 OK: $DEPLOYER` / `$OWNER` | STOP. A plain `--ledger` without the path returns `0x9Fc0...848d`: that is the path missing, not the device. Otherwise: wrong device or wrong PIN (passphrase). Owner: fix the MetaMask account/network. **P3 is re-run as a hard gate immediately before every deployer broadcast (2.2, 2.3, 4b)** |
| P4 | `powershell -File script/fork/size-liquidity.ps1 -Rpc $RPC` | last line `FUNDED` (owner >= leg + 0.002) | fund the owner (target 2.35 BNB); do NOT start |
| P5 | `cast call $DMX "owner()(address)"`, `"getUnlockTime()(uint256)"`, `"isExcludedFromFee(address)(bool)" $OWNER`, `"_maxTxAmount()(uint256)"` (all `--rpc-url $RPC`) | `$OWNER`, `0`, `true`, `1500000000000000000000000000` | owner authority changed or a `lock()` is running: the migration could never open. Do NOT deploy |
| P6 | `git describe --tags`; `git diff audit-final -- src/`; `forge test` | `launch-config-rc2` (or docs-only commits on top of it: `launch-config-rc2-N-g<commit>`); empty; 203 passed | wrong checkout |
| P7 | `Test-Path` on `deployments/two-phase-56.json`, `broadcast/DeployPhase1.s.sol/56`, `broadcast/DeployPhase2.s.sol/56`, `cache/DeployPhase1.s.sol/56`, `cache/DeployPhase2.s.sol/56` | all `False` | move the old files away: phase 2 and `--resume` would read them. A phase-1 **simulation** (2.1, or any dry run) WRITES `deployments/two-phase-56.json` and `broadcast/.../56/dry-run`: a dry run done before the day must be cleaned up again; the one in 2.1 is overwritten by 2.2 |
| P8 | on bscscan.com, `$DMX` -> Contract: the green "verified" tick and a **Write Contract** tab listing `approve`, `setMaxTxAmount`, `excludeFromFee`; same for `$ROUTER` (`swapExactETHForTokensSupportingFeeOnTransferTokens`) | present (both are exact matches on Sourcify: DMX since 2025-07-09) | the owner cannot sign 5a/9/11 through BscScan: stop and decide the signing path before phase 1 |
| P9 | MetaMask: Settings -> Advanced -> **Show hex data** ON; no pending transaction on `$OWNER`; the DMX token (`$DMX`) imported for display | done | turn it on: the hex data is how every owner confirmation is checked |

**The DMX owner must NEVER call `lock()` on DMX** -- nor
`renounceOwnership` or `transferOwnership` -- until 11b is done. The real
DMX is a SafeMoon-style `Ownable`: `lock(time)` sets `owner()` to zero until
`unlock()` after the lock time, and while it runs nobody can call
`setMaxTxAmount` or `excludeFromFee`: the window could not open while the
immutable 90-day deadline keeps running. On BscScan's Write Contract tab of
DMX, `lock`, `renounceOwnership`, `transferOwnership` and `presale` sit in
the same list as the three functions the owner uses: open only the
function each step names.

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
Assert-Deployer; forge script script/DeployPhase1.s.sol:DeployPhase1 --rpc-url $RPC --ledger --mnemonic-derivation-paths $DPATH --sender $DEPLOYER --legacy --with-gas-price $GP
# 2.2 broadcast -- ONE line: the gate, then the broadcast
Assert-Deployer; forge script script/DeployPhase1.s.sol:DeployPhase1 --rpc-url $RPC --ledger --mnemonic-derivation-paths $DPATH --sender $DEPLOYER --legacy --with-gas-price $GP --broadcast --slow
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
interrupted mid-broadcast: rerun the same 2.2 line (gate included) with
`--resume` added. If it reverts: read the
error; nothing is claimable yet (no 11b), the only cost is gas.

```powershell
# 2.3 phase 2 -- IMMEDIATELY, no other transaction from the deployer; ONE line: the gate (read-only), then the broadcast
Assert-Deployer; forge script script/DeployPhase2.s.sol:DeployPhase2 --rpc-url $RPC --ledger --mnemonic-derivation-paths $DPATH --sender $DEPLOYER --legacy --with-gas-price $GP --broadcast --slow
```
Check `[H2 F2.3, H2 F2.4]`: sixteen transactions; `All decentralization
asserts passed`; DaimonTimelock == `0xCdaa...0891`; fees 10/10/20; one
guardian expiry on three contracts; deployer nonce 19, about 0.00067 BNB
spent at 0.05 gwei. From here the deployer signs exactly ONE more
transaction: the LiquiditySeeder, step 4b. If the preflight
refuses: do NOT work around it -- abandon the phase-1 contracts and rerun
phase 1 fresh (new nonces, new addresses). If interrupted: the same 2.3
line (gate included) with `--resume` added.

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

## Step 4b -- the LiquiditySeeder -- DEPLOYER signs (Ledger, forge)

The seeder is launch tooling with an immutable caller: the constructor's
first argument, not the deployer, is the only address `seed` accepts. The
deployer deploys it with `$OWNER` there, so the owner never needs forge.

```powershell
cast nonce $DEPLOYER --rpc-url $RPC        # 19 -> the seeder lands at 0x21ab79825b86137CF1b04884FCFC4e4b717ce062
# ONE line: the gate, then the broadcast (--constructor-args must stay last)
Assert-Deployer; forge create script/launch/LiquiditySeeder.sol:LiquiditySeeder --rpc-url $RPC --ledger --mnemonic-derivation-path $DPATH --from $DEPLOYER --legacy --gas-price $GP --broadcast --constructor-args $OWNER $TOKEN $PAIR $WBNB $TL
$SEEDER    = "<Deployed to: from the output>"
$SEEDER_TX = "<Transaction hash: from the output>"
cast call $SEEDER "owner()(address)" --rpc-url $RPC        # $OWNER -- NOT $DEPLOYER
cast call $SEEDER "dmn()(address)" --rpc-url $RPC          # $TOKEN
cast call $SEEDER "pair()(address)" --rpc-url $RPC         # $PAIR
cast call $SEEDER "wbnb()(address)" --rpc-url $RPC         # $WBNB
cast call $SEEDER "timelock()(address)" --rpc-url $RPC     # $TL
cast call $SEEDER "used()(bool)" --rpc-url $RPC            # false
```
The constructor refuses a pair that is not the token's own DMN/WBNB pair
and a codeless Timelock `[H2 F5b.S1]`. If `owner()` is not `$OWNER`: the
seeder is useless (every `seed` reverts `NotOwner`) but harmless -- deploy
another one with the right argument; nothing else changes. A different
nonce only changes the seeder's address: use the one printed. After this
the deployer signs NOTHING.

## Step 4c -- verification, BEFORE any owner step

The owner signs through BscScan's Write Contract tab, which exists only
for a contract verified on BscScan. Every contract is verified now, before
the first owner click; the pair stays empty meanwhile (a 1-wei grief is
absorbed by the seeder, a material donation is refused by it, see 5b).

```powershell
powershell -File script/launch/verify-sourcify.ps1 -Chain 56 -Rpc $RPC -Seeder $SEEDER -SeederTx $SEEDER_TX
```
It reads every address, constructor argument and creation transaction from
the phase journals (the seeder's from its own getters), submits each
contract to **Sourcify**'s v2 API, polls the job, reads the verdict back,
and exits with the number of contracts not verified: expected exit 0, 7
contracts (implementation, proxy, Migration, Timelock, Staking, Governor,
LiquiditySeeder). Rehearsed on the Chapel 2b deployment: **7/7
exact_match**. Do NOT use `forge verify-contract --verifier sourcify`: with
forge 1.5.1 it printed "already verified" and verified nothing.

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
implementation's ABI. (Sourcify may forward a submission to Etherscan's
API on its own: look at the explorer page first, the form may already be
unnecessary.)

**Gate -- no owner step until all of these hold on bscscan.com:**

| address | page must show |
|---|---|
| `$MIG` (DaimonMigration) | verified; Write Contract lists `claim` |
| `$TOKEN` (DMN proxy) | verified; **Write as Proxy** lists `approve`, `transfer`; "Read as Proxy" `name()` answers |
| `$SEEDER` | verified; Write Contract lists `seed`; Read Contract `owner` == `$OWNER`, `used` == false |
| `$DMX`, `$ROUTER` | already verified (P8) |
| implementation, Timelock, Staking, Governor | verified (not written to on the day, verified anyway) |

## How the owner signs -- every owner step

The DMX owner `0xF8EC459CAEaF1052b64B38BDD67290B0c132B0Ae` signs in
**MetaMask**, through bscscan.com. For each step below the table gives the
contract, the function, the exact values to paste and what MetaMask must
show. The routine, every time:

1. Open the contract's page by pasting the address from this document into
   bscscan.com's search box -- never from a link in a chat, a mail or a
   search engine. Check the address in the page header, all of it.
2. Contract -> **Write Contract** (DMN: **Write as Proxy**) -> "Connect to
   Web3" -> MetaMask -> account `0xF8EC...B0Ae`. BscScan shows
   "Connected - Web3 [0xf8ec...]".
3. Expand ONLY the function the step names; paste the values in field
   order, digits only, no spaces, no thousands separators (uint256 fields
   take wei: the integer as printed, no decimal point). Click **Write**.
4. In MetaMask, before Confirm, check in this order:
   - network **BNB Smart Chain** (chain ID 56); account `0xF8EC...B0Ae`;
   - the contract it interacts with == the step's address (first and last
     characters at least, then all of it in the hex data);
   - the amount of BNB sent == the step's value (0 everywhere except `seed`
     and the test buy);
   - the **hex data** (P9: Show hex data) == the `expected data` the step
     prints with `cast calldata` -- the whole string; this is the check
     that matters, the decoded view can round a token amount;
   - no "this transaction is likely to fail" warning: a failing gas
     estimate means an on-chain check would revert -- **Reject** and read
     the step's failure notes;
   - network fee: a small fraction of 0.01 BNB. Anything near or above
     0.01: Reject and look again.
   - For an approval MetaMask shows a **spending cap request**: never
     click Edit / "use default" / "max" -- any change changes the hex and
     `ApprovalNotExact` / `AmountMismatch` follow.
5. Confirm; wait for "Success" on the BscScan transaction page; paste the
   hash into the launch record; run the step's read-only checks BEFORE the
   next step. "Speed up" in MetaMask is fine (same data); never "Cancel"
   and resend with edited values.

The expected data of every owner transaction is printed from the shell
where the variables live (`cast calldata` only encodes; it sends nothing).

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
$GROSS  = "<GROSS from the output>"      # rehearsed 4998406600825315109208480483; 2026-09-29 preflight 4999548574361503910682398180
$BNB    = "<BNB_LEG from the output>"    # rehearsed 2261000000000000000; 2026-09-29 preflight 1994000000000000000
cast --to-unit $BNB ether                # the leg in BNB, for the seed form (a multiple of 0.001: three decimals)
cast calldata "approve(address,uint256)" $MIG $GROSS     # expected data, 5a.1
cast calldata "claim(uint256)" $GROSS                    # expected data, 5a.2
```
If the helper does not print FUNDED: STOP before the claim. `$GROSS` and
`$BNB` are fixed here and used unchanged through 5b.

| # | contract (bscscan.com) | tab / function | paste, in field order | MetaMask must show |
|---|---|---|---|---|
| 5a.1 | DMX `0x36EbA94407B53c631eE822C219e94580fadd67c7` | Write Contract -> `approve` | spender: `$MIG` (`0x76368b60514b145617385847aCFF7b7EA9764725`); amount: `$GROSS` (wei) | spending cap request on DMX, spender `0x7636...4725`, cap `$GROSS` / 1e18 DMX (about 5.0 B); 0 BNB; hex data starts `0x095ea7b3` and == expected 5a.1 |
| 5a.2 | Migration `0x76368b60514b145617385847aCFF7b7EA9764725` | Write Contract -> `claim` | amount: `$GROSS` (wei) | interacting with `0x7636...4725`; 0 BNB; hex data starts `0x379607f5` and == expected 5a.2 |

Check after 5a.1: `cast call $DMX "allowance(address,address)(uint256)" $OWNER $MIG --rpc-url $RPC` == `$GROSS`.
Check after 5a.2 `[H2 F5a.5]`: `migratedAmount($OWNER)` == GROSS; the
owner's DMN == GROSS; `DMX.balanceOf($TL)` == GROSS -- 1:1 on every leg.
The owner can claim before 11b only because it is fee- and cap-exempt on
DMX `[H2 F5a.2]`. If the claim reverts with `AmountMismatch`: the owner
lost its DMX exemption -- STOP.

## Step 5b (with step 6 merged) -- the LiquiditySeeder -- DMX OWNER signs

```powershell
cast calldata "approve(address,uint256)" $SEEDER $GROSS  # expected data, 5b.1
cast calldata "seed(uint256)" $GROSS                     # expected data, 5b.2
```

| # | contract (bscscan.com) | tab / function | paste, in field order | MetaMask must show |
|---|---|---|---|---|
| 5b.1 | DMN proxy `0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a` | **Write as Proxy** -> `approve` | spender: `$SEEDER` (predicted `0x21ab79825b86137CF1b04884FCFC4e4b717ce062`); amount: `$GROSS` (wei) -- EXACTLY | spending cap request on DMN, spender == `$SEEDER`, cap `$GROSS` / 1e18; 0 BNB; hex data starts `0x095ea7b3` and == expected 5b.1 |
| 5b.2 | LiquiditySeeder `$SEEDER` | Write Contract -> `seed` | **payableAmount (BNB)**: the leg IN BNB, from `cast --to-unit $BNB ether` (e.g. `1.994` -- this field is in BNB, NOT wei); dmnGross: `$GROSS` (wei) | interacting with `$SEEDER`; amount **exactly the leg in BNB** (e.g. 1.994 BNB); hex data starts `0x95564837` and == expected 5b.2 |

`seed` is owner-only and single-use; in ONE transaction it moves the gross
DMN owner -> pair, wraps the BNB and sends it, calls `pair.mint(TIMELOCK)`,
and then refuses to finish unless: the pool price is within 0.10 % of
msg.value / DMN-received; every LP token is the Timelock's (`totalSupply -
1000`); nothing -- BNB, WBNB, DMN, LP -- is left in the seeder; the owner's
approval was exact (0 left). A wrong BNB amount typed in the payable field
is therefore caught on chain (`PriceOutOfTolerance`), but check it in
MetaMask anyway: 1.994 and 19.94 are one keystroke apart.

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

If MetaMask warns that `seed` is likely to fail, or it reverts:
`PriceOutOfTolerance`: someone parked a material amount in the pair (or
the BNB typed was wrong) -- STOP and decide (a donation of that size moves
the opening price; the seeder refuses it on purpose; unit test
`test_SkewingWbnbDonationBeyondToleranceReverts`). `ApprovalNotExact`:
re-approve exactly `$GROSS` (5b.1 again). `NotOwner` / `AlreadyUsed`:
wrong MetaMask account / the pool is already open -- read the pair before
anything else.

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

The owner holds no DMN after 5b, so the test sell needs a small buy first.
Three owner transactions, through the PancakeSwap v2 router's own verified
page (not the PancakeSwap app: the app picks its own route and slippage).

```powershell
$DEADLINE = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 1800; $DEADLINE    # paste this number; 30 minutes to do 9.1-9.3
cast calldata "swapExactETHForTokensSupportingFeeOnTransferTokens(uint256,address[],address,uint256)" 0 "[$WBNB,$TOKEN]" $OWNER $DEADLINE   # expected data, 9.1
# after 9.1 is mined:
$GOT = (cast call $TOKEN "balanceOf(address)(uint256)" $OWNER --rpc-url $RPC).Split(" ")[0]
$SELL = ([System.Numerics.BigInteger]::Parse($GOT) / 2).ToString(); $SELL
$P0 = (cast call $TOKEN "balanceOf(address)(uint256)" $PAIR --rpc-url $RPC).Split(" ")[0]
cast calldata "approve(address,uint256)" $ROUTER $SELL   # expected data, 9.2
cast calldata "swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)" $SELL 0 "[$TOKEN,$WBNB]" $OWNER $DEADLINE   # expected data, 9.3
```

| # | contract (bscscan.com) | tab / function | paste, in field order | MetaMask must show |
|---|---|---|---|---|
| 9.1 | Router `0x10ED43C718714eb63d5aA57B78B54704E256024E` | Write Contract -> `swapExactETHForTokensSupportingFeeOnTransferTokens` | payableAmount (BNB): `0.001`; amountOutMin: `0`; path: `[0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c,0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a]`; to: `0xF8EC459CAEaF1052b64B38BDD67290B0c132B0Ae`; deadline: `$DEADLINE` | interacting with `0x10ED...024E`; amount 0.001 BNB; hex data starts `0xb6f9de95` and == expected 9.1 |
| 9.2 | DMN proxy `0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a` | Write as Proxy -> `approve` | spender: `0x10ED43C718714eb63d5aA57B78B54704E256024E`; amount: `$SELL` (wei) | spending cap request on DMN, spender `0x10ED...024E`, cap `$SELL` / 1e18; 0 BNB; hex data starts `0x095ea7b3` and == expected 9.2 |
| 9.3 | Router `0x10ED43C718714eb63d5aA57B78B54704E256024E` | Write Contract -> `swapExactTokensForETHSupportingFeeOnTransferTokens` | amountIn: `$SELL`; amountOutMin: `0`; path: `[0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a,0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c]`; to: `0xF8EC459CAEaF1052b64B38BDD67290B0c132B0Ae`; deadline: the same `$DEADLINE` | interacting with `0x10ED...024E`; 0 BNB; hex data starts `0x791ac947` and == expected 9.3 |

The path fields: brackets, comma, no spaces; if BscScan refuses the
format, the same with each address in double quotes. The two paths are
opposite: 9.1 is WBNB then DMN, 9.3 is DMN then WBNB. If `$DEADLINE`
passes before 9.3 (`PancakeRouter: EXPIRED`): take a new one and re-print
the expected data. amountOutMin 0 is acceptable for a 0.001 BNB test; do
not reuse it for a real trade.

Check `[H2 F9.2]`: the pair's DMN `balanceOf` rose by EXACTLY
`SELL - floor(SELL x 10 / 1000) - floor(SELL x 30 / 1000)` (96 %, up to the
two floors: it can be 1-2 wei above `floor(SELL x 96 / 100)`); 95 % would
mean the historical 5 % fee. `cast balance $TOKEN` == 0 and `cast balance
$TL` == 0 (a router sell converts nothing, #1). Measure the pair by
`balanceOf`, not reserves.

## Step 10 -- the first poke -- DMX OWNER signs

```powershell
cast calldata "transfer(address,uint256)" $PAIR 1        # expected data, 10
```

| # | contract (bscscan.com) | tab / function | paste, in field order | MetaMask must show |
|---|---|---|---|---|
| 10 | DMN proxy `0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a` | Write as Proxy -> `transfer` | to: `$PAIR` (`0x40A97Ae210a44057603186B4BE92BAe719342AFA`); amount: `1` (wei) | interacting with `0x1608...be6a` (MetaMask may display it as a token send of 0.000000000000000001 DMN to `0x40A9...2AFA`); 0 BNB; hex data starts `0xa9059cbb` and == expected 10 |

**Expected: the poke converts NOTHING.** The fee inventory is ~0.15 B (3 %
of the 5b transfer), below the 0.2 B threshold `[H2 F10.1]`: `cast balance
$TL` == 0, `cast balance $STAKING` unchanged, the inventory unchanged. That
is the correct launch-day result, not a failure. The first conversion comes
later, once about 1.66 B of further taxed volume has armed it: one 0.2 B
chunk sells, 20/30 of the BNB to staking, 10/30 kept for buyback, ZERO to
the Timelock, price about -7.8 % on the launch pool `[H2 F10.2, H2 F10.3]`.
A Timelock BNB balance above 0 at share 1000 is a stop-everything signal.

## Step 11a, then 11b -- the window opens -- DMX OWNER signs, back to back

The expected data of both is fixed (they depend only on the cap and the
Timelock address of the table above):

```powershell
cast calldata "setMaxTxAmount(uint256)" 1000000000000000000000000000000   # 11a: 0xec28438a000000000000000000000000000000000000000c9f2c9cd04674edea40000000
cast calldata "excludeFromFee(address)" $TL                              # 11b: 0x437823ec000000000000000000000000cdaa1cfe783a4de642ca3ed98a38bfdc16f30891
```

| # | contract (bscscan.com) | tab / function | paste, in field order | MetaMask must show |
|---|---|---|---|---|
| 11a | DMX `0x36EbA94407B53c631eE822C219e94580fadd67c7` | Write Contract -> `setMaxTxAmount` | maxTxAmount: `1000000000000000000000000000000` (1 followed by 30 zeros = 1e12 tokens) | interacting with `0x36Eb...67c7`; 0 BNB; hex data == `0xec28438a000000000000000000000000000000000000000c9f2c9cd04674edea40000000` |
| 11b, LAST | DMX `0x36EbA94407B53c631eE822C219e94580fadd67c7` | Write Contract -> `excludeFromFee` | account: `$TL` (`0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891`) | interacting with `0x36Eb...67c7`; 0 BNB; hex data == `0x437823ec000000000000000000000000cdaa1cfe783a4de642ca3ed98a38bfdc16f30891` |

On this tab, `excludeFromFee` sits next to `includeInFee`, `excludeFromReward`
and `includeInReward`; `setMaxTxAmount` next to `setTaxFee`,
`setMarketingFee`, `setBuybackFee` and the other setters (the real DMX's
write tab, from its Sourcify ABI); `approve` (5a.1) next to
`increaseAllowance` and `deliver`: the hex data is what tells them apart. And `lock` is on the
same tab: see the rule under the preflight.

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
signer); the owner's whole signing path -- MetaMask through BscScan's Write
Contract tab -- and the seeder deployed by the deployer instead of the owner
(same contract, same constructor arguments, a different sender and
address); BscScan's web form (Sourcify was rehearsed on Chapel instead); the
public mempool against a real adversary (the grief was rehearsed, mined, by
an impersonated stranger); real time between steps (the fork mined each
transaction instantly: 11a and 11b one block apart); the monitor watching;
the migration deadline itself.
