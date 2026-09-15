# Chapel "2b" mini-campaign -- results (branch chapel/level-2b)

**Status: IN PROGRESS.** Day 0 is local (Anvil forking BSC Chapel).
Day 1 (2026-09-14) is on BSC Chapel: contracts, liquidity, first poke, 11a/11b
and proposal 0 are live on a public chain; the governance cycle runs on
the real clock from here. Resuming after a crash or a new session =
start from the first scenario not yet committed in this file.

## What this mini-campaign is

Level 2 proved the audited contracts on Chapel in real time, with the
launch scripts as they were on 2026-08-28. Since then the launch decisions
changed the SCRIPTS, not the contracts (`src/` stays frozen at
`audit-final`): the marketing wallet is the Timelock, the 4% fee model is
set at deploy instead of by a 13-day proposal, the post-broadcast gate
grows from 34 to 36 checks, the LP tokens go to the Timelock as a launch
step, and the predecessor mock carries the real DMX transfer cap. This
level proves those script changes -- first on a fork (Day 0), then on
Chapel.

## Day 0 scope (H0)

| item | change | where |
|---|---|---|
| H0.1 | `marketingWallet` defaults to the predicted Timelock; `MARKETING_WALLET` stays an explicit, loudly logged override | `script/DeployPhase1.s.sol` |
| H0.2 | `setFees(10, 10, 20)` through the deployer's temporary GOVERNANCE_ROLE, before it is handed to the Timelock; asserted in phase 2 | `script/DeployPhase2.s.sol` |
| H0.3 | two new read-only checks: `fees == (10,10,20)` and `marketingWallet == the deployed Timelock` (34 -> 36) | `script/verify-deploy.ps1` |
| H0.4 | launch step 6: ALL LP tokens deployer -> Timelock, asserted from mined state | `script/campaign/lib.ps1` (`Move-LpToTimelock`) |
| H0.5 | the predecessor mock models `_maxTxAmount` (1.5B, owner-exempt, fee exemption does not lift it) and `setMaxTxAmount` (onlyOwner) | `script/campaign/CampaignOldDaimon.sol` |
| H0.6 | tests for H0.5; the existing 180 untouched | `test/OldDaimonMaxTx.t.sol` |

## Harness (Day 0)

| piece | choice |
|---|---|
| Chain | Anvil forking **BSC Chapel** (chain id 97) at a pin resolved per sitting (`script/campaign/forkpin.txt`) |
| Why a fork | the real PancakeSwap V2 router/factory serve `initialize()`, the pool, the sells and the pokes |
| Deploy under test | the real `DeployPhase1.s.sol` + `DeployPhase2.s.sol`, broadcast against the node, then `script/verify-deploy.ps1` |
| Predecessor | `script/campaign/CampaignOldDaimon.sol` with the H0.5 cap; the deployer is its owner and its fee-exempt distributor (Level 1 model, 1,000 B) |
| Marketing wallet | **the Timelock** (H0.1): no `MARKETING_WALLET` in the environment |
| Time | Anvil RPC only (`evm_increaseTime`, `anvil_mine`) |
| Runners | `script/campaign/H1.ps1`, `H2.ps1`, `H3.ps1`, one per scenario, each on a fresh node; rows appended here by the runner |

Roles as in Level 1 (public dev mnemonic, sanitized on the local fork):
`deployer` (also the mock's owner), `guardian`, `alice`/`bob` (holders),
`team1`, `tp1` (migrating holders: 213.56 B and 76.90 B), `stranger` (the
poke, queue, execute). The Level-1 keyless sentinel `0x...A001` is no longer
wired anywhere and is checked to stay at zero anyway.

---

# Results

## Day 0 -- Anvil (2026-09-12)


### H1 -- Launch order 1-11b on the fork: new defaults, 36-check gate, LP to the Timelock, 4% fee, first poke, 11a then 11b

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| H1.1 | Step 1: DMN/WBNB pair on the factory BEFORE phase 1 (#25) | none: getPair(predicted proxy, WBNB) == 0x0 | predicted proxy=0xE88995f41aE91eEF0c9Cb66ad23b5831d4702CCA (deployer nonce 19676 + 1), getPair=0x0000000000000000000000000000000000000000 | PASS |
| H1.2 | Step 2: phase 1 + phase 2 broadcast against the live node, no env override | five contracts up; state file records treasuryOverridden=false AND marketingWalletOverridden=false | token=0xE88995f41aE91eEF0c9Cb66ad23b5831d4702CCA, timelock=0x20211Cc856d7522412b8d39767Bf7a3f6719E50a, governor=0x52a097332b571ccF720FC02312cD4165e9BF87bA; treasuryOverridden=False, marketingWalletOverridden=False, MARKETING_WALLET env present=no | PASS |
| H1.3 | H0.1 -- the marketing wallet, read from the live token | it IS the timelock deployed in phase 2: the same prediction as the migration treasury and governance, all three fulfilled | token.marketingWallet=0x20211Cc856d7522412b8d39767Bf7a3f6719E50a, migration.treasury=0x20211Cc856d7522412b8d39767Bf7a3f6719E50a, migration.governance=0x20211Cc856d7522412b8d39767Bf7a3f6719E50a, timelock=0x20211Cc856d7522412b8d39767Bf7a3f6719E50a | PASS |
| H1.4 | H0.2 -- the fees, read from the live token right after phase 2 | 10/10/20, liquidityFee 30: the 4% model live from the first block, no proposal needed | taxFee=10 buybackFee=10 marketingFee=20 liquidityFee=30 (total 4%) | PASS |
| H1.5 | The rest of the phase-2 configuration, live | share 1000; one expiry across the three contracts; the whole supply in the migration | share=1000; expiry token=1883775148 timelock=1883775148 governor=1883775148; supply=1000.0000 B in migration=1000.0000 B | PASS |
| H1.6 | Step 3: script/verify-deploy.ps1 against the live node (H0.3: 34 -> 36 checks) | 36/36 green, exit code 0 -- the MANDATORY GATE | exit=0; Post-broadcast verification -- chain 97 VERIFICATION PASSED: 36/36 checks green against live chain state. | PASS |

Full output of the verification, verbatim:

```
Post-broadcast verification -- chain 97
State file: C:\Users\Utente\Desktop\Daimon dao\deployments\two-phase-97.json


check                                                  expected                                   observed                                   verdict
-----                                                  --------                                   --------                                   -------
code at token                                          present                                    present                                    PASS
code at timelock                                       present                                    present                                    PASS
code at governor                                       present                                    present                                    PASS
code at staking                                        present                                    present                                    PASS
code at migration                                      present                                    present                                    PASS
token: timelock holds GOVERNANCE_ROLE                  true                                       true                                       PASS
token: deployer lacks GOVERNANCE_ROLE                  false                                      false                                      PASS
token: deployer lacks DEFAULT_ADMIN                    false                                      false                                      PASS
token: guardian holds GUARDIAN_ROLE                    true                                       true                                       PASS
token: stakingRewardShareBps == 1000                   1000                                       1000                                       PASS
token: stakingContract is the staking                  0xCa901bb81b3467A1BF079003c9c5Bd41a4041891 0xCa901bb81b3467A1BF079003c9c5Bd41a4041891 PASS
token: marketingWallet as configured                   0x20211Cc856d7522412b8d39767Bf7a3f6719E50a 0x20211Cc856d7522412b8d39767Bf7a3f6719E50a PASS
token: migration is fee-exempt                         true                                       true                                       PASS
token: fees == (10,10,20)                              10,10,20                                   10,10,20                                   PASS
timelock: self-administers                             true                                       true                                       PASS
timelock: deployer lacks ADMIN_ROLE                    false                                      false                                      PASS
timelock: deployer lacks PROPOSER_ROLE                 false                                      false                                      PASS
timelock: deployer lacks EXECUTOR_ROLE                 false                                      false                                      PASS
timelock: governor is proposer                         true                                       true                                       PASS
timelock: governor is executor                         true                                       true                                       PASS
timelock: guardian is canceller                        true                                       true                                       PASS
timelock: governor is canceller                        true                                       true                                       PASS
timelock: self-cancel role present                     true                                       true                                       PASS
expiry: timelock == token (exact)                      1883775148                                 1883775148                                 PASS
expiry: governor == token (exact)                      1883775148                                 1883775148                                 PASS
staking: timelock is governance                        true                                       true                                       PASS
staking: deployer is not governance                    false                                      false                                      PASS
supply: totalSupply == INITIAL_SUPPLY                  1000000000000000000000000000000            1000000000000000000000000000000            PASS
supply: all of it in the migration                     1000000000000000000000000000000            1000000000000000000000000000000            PASS
migration: governance is the timelock                  0x20211Cc856d7522412b8d39767Bf7a3f6719E50a 0x20211Cc856d7522412b8d39767Bf7a3f6719E50a PASS
migration: newDaimon is the token                      0xE88995f41aE91eEF0c9Cb66ad23b5831d4702CCA 0xE88995f41aE91eEF0c9Cb66ad23b5831d4702CCA PASS
migration: oldDaimon as configured                     0x7b331c59e5f9139923a06EA0B06CEa36cE9CF5d7 0x7b331c59e5f9139923a06EA0B06CEa36cE9CF5d7 PASS
migration: treasury as configured                      0x20211Cc856d7522412b8d39767Bf7a3f6719E50a 0x20211Cc856d7522412b8d39767Bf7a3f6719E50a PASS
migration: treasury is the timelock                    0x20211Cc856d7522412b8d39767Bf7a3f6719E50a 0x20211Cc856d7522412b8d39767Bf7a3f6719E50a PASS
token: marketingWallet is the deployed timelock (live) 0x20211Cc856d7522412b8d39767Bf7a3f6719E50a 0x20211Cc856d7522412b8d39767Bf7a3f6719E50a PASS
token: pancake pair created                            present                                    present                                    PASS



Guardian expiry raw values: token=1883775148 timelock=1883775148 governor=1883775148
VERIFICATION PASSED: 36/36 checks green against live chain state.

```
| H1.7 | A non-exempt holder tries to claim 1.00 B after the gate, BEFORE 11b | refused with AmountMismatch (#29): no claim is possible against this deployment yet | reverted with AmountMismatch | PASS |
| H1.8 | Step 4: automation state before liquidity (#27) | enabled by initialize, inert by construction: no inventory, no reserves, pokes are the only trigger | swapAndLiquifyEnabled=true buyBackEnabled=true, inventory=0.0000 B, pair reserves=(0,0) by construction | PASS |
| H1.9 | Step 5 prerequisite: team1 sends the deployer 12.00 B DMX, the deployer migrates 10.00 B for the pool and the later steps | exact on both transfers -- on the fork the deployer is fee-exempt on the mock (as recipient and as sender) AND its owner (cap-exempt) | deployer DMX after funding=12.0000 B, deployer DMN=10.0000 B; mock: excludedFromFee(deployer)=true, owner=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 | NOTE |
| H1.10 | Step 5: deployer adds 4.00 B gross + BNB computed on the NET receipt | reserve DMN == 4.00 B x 0.96 = 3.84 B (the 4% fee, not 5%); opening price exactly 1e9 DMN/BNB | reserve DMN=3.8400 B (net expected 3.8400 B), BNB=3.8400, implied=1000000000 DMN/BNB | PASS |
| H1.11 | Step 6: ALL the LP tokens, deployer -> Timelock, one published transaction (H0.4) | from mined state: pair.balanceOf(deployer) == 0 and pair.balanceOf(timelock) == pair.totalSupply() - MINIMUM_LIQUIDITY (1000 wei) | moved=121431462150465766347757 wei LP; deployer LP=0, timelock LP=121431462150465766347757, totalSupply=121431462150465766348757, MINIMUM_LIQUIDITY=1000; tx=0x1feea302b6afe80cec89c53f5a46429cb335a51fe617392f5ef135e5dd12b631 | PASS |
| H1.12 | Step 7: the pair the token stores vs the pair the factory created | identical | token.uniswapV2Pair=0xDE6095184ceB55FB3Bb90429Bd0a9a06b1355D35, factory.getPair=0xDE6095184ceB55FB3Bb90429Bd0a9a06b1355D35 | PASS |
| H1.13 | Step 8: both reserves non-zero | automation can now run on a real pool | DMN=3.8400 B, BNB=3.8400 | PASS |
| H1.14 | Step 9: deployer sells 0.05 B through the real router | the pair receives EXACTLY 96% of the amount sent (fee 4%), NOT 95% | pair DMN reserve +48000000000000000000000000 wei = 0.0480 B (96% would be 48000000000000000000000000, 95% would be 47500000000000000000000000); inventory +0.0015 B (>= the 3% liquidityFee share: 0.0015 B) | PASS |
| H1.15 | Did the router sell trigger any conversion? (#1) | no: router-initiated transfers skip the automation, inventory only grew | inventory 0.1200 B -> 0.1215 B, contract BNB=0.0000 | PASS |
| H1.16 | Inventory armed by ordinary transfers (4.00 B to alice, 0.50 B to the stranger) | inventory >= minimumTokensBeforeSwap; Timelock BNB still zero | inventory=0.2565 B vs threshold 0.2000 B; timelock BNB=0.0000, staking BNB=0.0000, contract BNB=0.0000 | PASS |
| H1.17 | Step 10: the stranger pokes (1 wei of DMN to the pair) | exactly ONE threshold-sized chunk converts (#28 budget); the call succeeds | consumed=0.2000 B vs threshold 0.2000 B; tx=0xeab576f1b97f51cfb7d8a91597f0618f86e0039fe59b272540e27be1412b3e5d | PASS |
| H1.18 | Where the BNB went, with stakingRewardShareBps == 1000 | the WHOLE marketing share (20/30 of the proceeds) to the staking pool, the buyback share retained by the token, and NO BNB from the token to the Timelock -- the marketing-wallet branch is not entered | received=0.1851 BNB: staking +0.1234, contract +0.0617, TIMELOCK +0.0000; marketing share computed=0.1234 | PASS |
| H1.19 | The marketing wallet (= the Timelock) after the first conversion | zero DMN, zero BNB delta: it received nothing | timelock DMN=0, timelock BNB delta=0 | PASS |
| H1.20 | Step 11a: the DMX owner raises _maxTxAmount (H0.5 model) | 1.50 B before (the real value); the new value read back from the chain | maxTxAmount 1.5000 B -> 1000.0000 B | PASS |
| H1.21 | Step 11b: excludeFromFee(TIMELOCK) on the predecessor -- the TREASURY, not the Migration | exemption active on the timelock, none on the migration | excludedFromFee(timelock)=true, excludedFromFee(migration)=false | PASS |
| H1.22 | The same holder refused in H1.7 claims 1.00 B now | exact 1:1: the Timelock (treasury) receives exactly 1.00 B of the predecessor, team1 exactly 1.00 B DMN | treasury old +1.0000 B, team1 DMN +1.0000 B | PASS |

Launch-order finding surfaced by H1.9, recorded and NOT worked around: step 5 (initial liquidity) needs DMN in the deployer's hands, and the only source of DMN is claim() -- which the checklist opens at step 11b, six steps later. On this fork the deployer's claim passes only because the harness makes the deployer the mock's fee-exempt distributor AND its owner. On mainnet the deployer is a dedicated Ledger, not the DMX owner and not exempt: the DMX it receives arrives net of the 11% fee, and its pre-11b claim would revert with AmountMismatch (the 11% DMX fee on the deployer -> Timelock leg) and, above 1.5B, with the cap. The order needs an explicit extra owner call BEFORE step 5 -- DMX excludeFromFee(deployer) (from-side exemption; the cap still binds at 1.5B per claim unless 11a moves earlier too) -- or the liquidity must be provided by an address that already holds DMN. Decision is the operator's; the checklist does not list this call today.

### H2 -- The 1.5B DMX cap binds claim(): a 3B claim reverts before setMaxTxAmount, passes after (exact 1:1)

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| H2.1 | Predecessor state: 11b done, 11a deliberately NOT done | maxTxAmount == 1.50 B (the real DMX value); treasury exempt; tp1 is a plain holder (not the owner, not exempt) with 76.90 B | maxTxAmount=1.5000 B, excludedFromFee(timelock)=true, owner=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, tp1 old balance=76.9000 B, tp1 exempt=false | PASS |
| H2.2 | tp1 claims 3.00 B (twice the cap) with the exemption in place | REVERTS with the predecessor's own cap message: the fee exemption does NOT lift the cap | reverted with Transfer amount exceeds the maxTxAmount. | PASS |
| H2.3 | State after the refused claim | nothing moved, nothing credited: treasury old delta 0, tp1 DMN 0, migratedAmount 0 | treasury old delta=0.0000 B, tp1 DMN=0.0000 B, migratedAmount=0.0000 B | PASS |
| H2.4 | tp1 claims exactly 1.50 B | passes: the cap is inclusive; exact 1:1 | treasury old +1.5000 B, tp1 DMN=1.5000 B | PASS |
| H2.5 | Step 11a: setMaxTxAmount(1000.00 B) -- a holder first, then the owner | the holder is refused (onlyOwner); the owner's call is read back from the chain | tp1: reverted with DMX: only owner; owner: maxTxAmount 1.5000 B -> 1000.0000 B | PASS |
| H2.6 | tp1 claims the same 3.00 B after 11a | passes: 1:1, no fee on either leg -- the treasury receives EXACTLY 3.00 B of mock DMX, tp1 EXACTLY 3.00 B DMN, tp1's old balance down by exactly 3.00 B | treasury old +3.0000 B (3000000000000000000000000000 wei), tp1 old -3.0000 B, tp1 DMN +3.0000 B (3000000000000000000000000000 wei), migratedAmount=4.5000 B | PASS |
| H2.7 | The marketing wallet (= the Timelock) through the scenario | zero DMN, zero BNB | DMN=0, BNB=0.0000 | PASS |

This is launch order step 11a earning its place: with the exemption alone, every holder above 1.5B is locked out by a revert that comes from the predecessor, not from the migration -- the 76.9B top holder included. The cap is a plain owner setting, and once raised the same claim clears exactly, to the wei, on both legs.

### H3 -- setStakingRewardShareBps(600) by governance (warped), then the first poke that pays the marketing branch: 40% to the Timelock, call succeeds

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| H3.1 | Launch state before the vote | share 1000, marketing wallet == Timelock, inventory armed, Timelock BNB zero | share=1000, marketingWallet=0x20211Cc856d7522412b8d39767Bf7a3f6719E50a (timelock=0x20211Cc856d7522412b8d39767Bf7a3f6719E50a), inventory=0.3750 B vs threshold 0.2000 B, timelock BNB=0.0000, LP in timelock=121431462150465766347757 | PASS |
| H3.2 | propose -> (1 day) vote -> (5 days) queue; execute attempted at once | Pending, Active, Succeeded, Queued; the early execute is refused by the 7-day timelock | after propose=Pending, after vote=Active, after voting=Succeeded, after queue=Queued; early execute: reverted | PASS |
| H3.3 | execute after 7 warped days | Executed; stakingRewardShareBps == 600 on the live token | state=Executed, share 1000 -> 600 | PASS |
| H3.4 | The stranger pokes with 0.3750 B of inventory | the call succeeds (status 0x1, no revert on the Timelock leg) and exactly one chunk converts | tx=0x4947657a9b3ce1ce0ca0f391c46bcb430b2519d2380577d3d7092eb4f2328126, consumed=0.2000 B vs threshold 0.2000 B | PASS |
| H3.5 | Where the BNB went, with share 600 | marketing share = received x 20/30; 60% of it to staking, 40% to the TIMELOCK (marketing wallet), the buyback share retained -- every leg exact to the wei | received=0.1897: staking +0.0758 (expected 0.0758), TIMELOCK +0.0505 (expected 0.0505), contract +0.0632 (expected 0.0632); timelock share of marketing = 400 per mille | PASS |
| H3.6 | The Timelock's BNB balance across the whole scenario | zero from deploy until this poke, then up by exactly the 40% share -- the first BNB the treasury ever receives from the token | 0.0000 -> 0.0000 (before the poke) -> 0.0505 | PASS |
| H3.7 | The Level-1 keyless sentinel (0x...A001), no longer the marketing wallet | untouched: it is not wired anywhere on this deploy | DMN=0, native=0.0000 | PASS |

The branch that never ran in Level 1 or on Chapel -- marketingWallet.call{value}(...) -- ran here for the first time, against the Timelock, and did not revert: the Timelock's receive() takes the BNB and the split lands to the wei on all three legs. Restoring an operational share is therefore a one-proposal change with no wiring to touch, exactly as the deploy comment says.


## Day 0 status (2026-09-12) -- Anvil only, nothing on a public chain

**3 scenarios, 36 asserted rows: 35 PASS, 1 NOTE (H1.9), 0 DEVIATION.**
Verification gate on the fork: **36/36**. The H0 changes are implemented on
`chapel/level-2b` and rehearsed; none of it is merged.

| scenario | rows | result |
|---|---|---|
| H1 -- launch order 1-11b, new defaults, 36-check gate, LP to the Timelock, 4% test swap, first poke (share 1000: 0 BNB to the Timelock), 11a then 11b | 22 | 21 PASS, 1 NOTE |
| H2 -- the 1.5B DMX cap against claim(): 3B refused before setMaxTxAmount, exact 1:1 after | 7 | PASS |
| H3 -- setStakingRewardShareBps(600) by warped governance, then the first poke that pays the marketing branch: 40% to the Timelock, no revert | 7 | PASS |

### Gate

- `git diff audit-final -- src/`: **empty** (no contract touched; H0.5 lives
  in the campaign mock, see below).
- `forge test`: **187 passed, 0 failed** = the 180 existing + 7 new in
  `test/OldDaimonMaxTx.t.sol`. No existing assert or test was adapted.
- Assert counts after H0: phase 1 = 10 (the marketing-wallet assert now
  compares against the PREDICTED timelock on the default path), phase 2 =
  25 (20 + 4 fee-model + 1 marketing linkage), post-broadcast verification
  = 36.

### Findings and deviations from the brief, recorded not hidden

1. **Launch-order gap at step 5 (protocol-side, decision needed).** Initial
   liquidity needs DMN in the deployer's hands, and the only source of DMN
   is `claim()`; the checklist opens claims at step 11b, six steps later. On
   the fork the deployer's pre-11b claim passes only because the harness
   makes it the mock's owner AND fee-exempt distributor (H1.9, NOTE). On
   mainnet the deployer is a dedicated Ledger with neither property: the
   claim would revert with `AmountMismatch` (11% DMX fee on the deployer ->
   Timelock leg) and, above 1.5B, with the cap. The order needs either an
   extra DMX owner call before step 5 -- `excludeFromFee(deployer)`, with
   the cap still binding at 1.5B per claim unless 11a moves earlier -- or a
   liquidity provider that already holds DMN. Not worked around here.
2. **`docs/SCENARI_2B.md` does not exist** in the working tree, in any
   branch or anywhere in the history. Day 0 was implemented from the
   H0.1-H0.6 specification given in the brief, which is self-contained;
   the scenario names H1/H2/H3 are this journal's, and should be aligned to
   the plan once it lands in the repo.
3. **`MockOldDaimon.sol` lives in `src/mocks/`, not `test/mocks/`,** and is
   part of the frozen `audit-final` range. Touching it would break the
   src/ gate, so H0.5 was applied to `script/campaign/CampaignOldDaimon.sol`
   only -- the DMX-faithful mock the fork AND the Chapel campaigns deploy
   -- and the H0.6 tests exercise that contract. `DeployPhase1`'s
   "mock on testnet if OLD_DAIMON is unset" path still deploys the src mock
   (no cap, 5% fee, permissionless exemptions); every campaign passes
   `OLD_DAIMON` explicitly, so the path is not exercised.
4. **Harness error on the first H1 attempt, corrected and recorded.** The
   Level-1 distribution model hands the whole 1,000 B of mock DMX to the
   modelled holders, so the deployer owns none; the first run died at H1.9
   with `Panic(17)` (underflow) on the deployer's claim. The runner now has
   team1 fund the deployer with 12 B first. No protocol behaviour involved.
5. **A Level-2 runner's expectation is now stale by design.** With fees
   set in phase 2, `script/chapel/CH-P6.ps1` row P2.1d.3 ("fees BEFORE
   execute == 10/20/20/40") would read DEVIATION on any future deploy: on
   the 2b deploy there is no 5% state to move away from. The Level-1
   runner D4.5 asserts only the post-execute values and still holds. Not
   adapted (the closed campaign is history); to be decided with the Chapel
   plan.
6. **Docs not updated on this branch:** `CHECKLIST_MAINNET.md` and
   `DEPLOY.md` still describe the two checks as "PLANNED" (34 today, 36
   once they land) and phase 2 as 20 asserts. Left for the operator's
   review pass, since both files carry launch decisions.

### What Day 0 does not cover

Real block times and mempool ordering, real gas, the 7-day timelock on a
real clock, and the two DMX owner calls (11a/11b) signed by the real DMX
owner -- that is the Chapel part of this mini-campaign, and it starts only
once the diff above has been reviewed.

## Day 1 -- Chapel (2026-09-14)

First broadcast on BSC Chapel (chain id 97) of the launch-script changes
rehearsed on the fork on Day 0. Same method as Level 2: real keystores,
real blocks, real gas, one second per second; every state-changing step
records its transaction hash; every value asserted is read from MINED
state; no assert is ever adapted. One script change landed between Day 0
and today, committed on its own: the MARKETING_WALLET override is refused
on chain 56 exactly as the treasury override is (DeployPhase1, re-guarded
in DeployPhase2). Neither override is set here.

### Harness (Day 1)

| piece | choice |
|---|---|
| Chain | BSC Chapel (97), RPC `https://bsc-testnet.publicnode.com` -- the harness refuses any other chain id at load |
| Roles | TWO signing roles mirror mainnet: **deployer** (phases 1 and 2, the verification, and NOTHING between the phases) and **oldowner** (owner of the CampaignOldDaimon mock: the liquidity claim, the liquidity, LP to the Timelock, 11a/11b). Two campaign roles: **holder** (non-owner claimant, staker, proposer) and **stranger** (test sell, poke) |
| Guardian | the test Safe `0x4253f80666E48a04CAbE4966Aa63035Dbb4f104F` (2 of 3), never signs through this harness |
| Marketing wallet | the Timelock (H0.1): no `MARKETING_WALLET` in the environment, no treasury override |
| Predecessor | `script/campaign/CampaignOldDaimon.sol` (11% fee, owner-gated exemptions, the 1.5B cap of H0.5), deployed and owned by **oldowner** |
| Opening price | a PARAMETER: 4.69e-10 BNB/token (read 2026-09-10 from the DMX pool) = 469000000 wei per whole DMN. Liquidity sizing per decision (c) on the maxTx finding: the largest single addLiquidityETH the token's 5B maxTx allows (mainnet: 5B gross, 4.8B net, 2.2512 BNB), scaled on Chapel to the tBNB oldowner holds; the DMN leg is derived from the BNB at that ratio and sent gross so the pair receives the net (#17) |
| Invariant | after every signed send: the Timelock holds 0 native and 0 DMN -- with share 1000 nothing reaches it from the token (its predecessor-token balance grows with claims, its LP balance is set at step 6: neither is a token payout) |
| Signing | `cast send --account <keystore> --password-file <path>`; names, addresses and the path live in `script/chapel2b/keystore-map.json` (gitignored) |
| Runners | `script/chapel2b/H1a..H1f`, `H2`, `H3a` -- one per sitting, rows appended here by the runner, state carried in `script/chapel2b/state.json` (gitignored) |

### Account safety (read at block 130963606, before any campaign transaction)

Funding, the only value transfer of the day and the FIRST transaction: deployer -> oldowner 0.2000 tBNB, tx 0x7679813c28a701a3cd91b59d82b7b93fad089e38f7c384017d52d0553dcc2ccf -- done before phase 1, so the deployer signs nothing between the two phases. The liquidity leg lives with the mock owner, as it will on mainnet with the DMX owner.

| role | address | code | balance | nonce |
|---|---|---|---|---|
| deployer | 0x052bB2834d292d078cf686F5f4BB2bb55E424943 | `0x` (none) | 0.0484 tBNB | 45 |
| oldowner | 0xD7ca3011eB7Caae4A76c245c93FaAc56A7F58DaE | `0x` (none) | 0.2800 tBNB | 0 |
| holder | 0x583982463dA108879566868506Cba32E7b023576 | `0x` (none) | 0.1119 tBNB | 14 |
| stranger | 0x05Eb589Cba778FdFeE6bf2Dc0C1EFd32b48006e2 | `0x` (none) | 0.0798 tBNB | 4 |
| guardian (Safe) | 0x4253f80666E48a04CAbE4966Aa63035Dbb4f104F | contract (344 chars) | 0.0000 tBNB | -- |

Every signing role: no code (no EIP-7702 delegation, no contract). The
deployer is the Level-2 deployer, its nonce is not virgin: the two-phase
predictions are computed from the LIVE nonce, as the scripts do.

---

### H1 (0) -- The predecessor mock: deployed and owned by oldowner, the real 1.5B cap, no exemption for the treasury yet

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| H1.0.1 | CampaignOldDaimon deployed by oldowner, supply minted to oldowner | totalSupply == 1e30; owner() == oldowner; maxTxAmount == 1.5B (the real DMX value, read 2026-09-11) | old=0xb0aA935f46354501d622C4A11a554CE226ADAE28, totalSupply=1000000000000000000000000000000, owner=0xD7ca3011eB7Caae4A76c245c93FaAc56A7F58DaE, maxTxAmount=1.5000 B (1500000000000000000000000000 wei) (2026-09-14 10:05 UTC) | 0xbb21d596d6429e8fa70c9d461ce3fd19165fdbac7d1d3b35bb61af0cdd713fe7 | PASS |
| H1.0.2 | Owner self-exemption on the mock (exact distribution; and the property step 5a relies on) | excludedFromFee(oldowner) == true; the owner is cap-exempt by construction (from/to owner) | excludedFromFee(oldowner)=true, owner=0xD7ca3011eB7Caae4A76c245c93FaAc56A7F58DaE (2026-09-14 10:05 UTC) | 0xa94815895aaf6518b9189ad28e256fddaf6120efde867e3d105c5adea8858f8c | PASS |
| H1.0.3 | Distribute 5.00 B of mock DMX to the holder (the non-owner claimant of H1 and H2) | exact credit: 5000000000000000000000000000 wei (sender exempt, no fee; sender is the owner, no cap) | holder old balance=5.0000 B (5000000000000000000000000000 wei) (2026-09-14 10:05 UTC) | 0xab5b7b8209096f52ebf53b943af1345327794ca1a87b1b2be6d3f19196699fba | PASS |
| H1.0.4 | The holder and the deployer on the mock | neither is the owner, neither is fee-exempt: on this predecessor only oldowner can move DMX without fee or cap | excludedFromFee(holder)=false, excludedFromFee(deployer)=false, owner=0xD7ca3011eB7Caae4A76c245c93FaAc56A7F58DaE (2026-09-14 10:05 UTC) | - | PASS |
| H1.0.5 | Treasury exemption and cap on the mock | NOT set, NOT raised: 11a/11b come last (H2), after the gate, the liquidity and the first poke | excludedFromFee(<timelock>) cannot exist yet (no timelock); maxTxAmount=1.5000 B (2026-09-14 10:05 UTC) | - | PASS |

### H1 (1-2) -- Step 1: no pair pre-exists; step 2 phase 1: marketingWallet == predicted Timelock, read from mined state

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| H1.1 | Step 1: DMN/WBNB pair on the factory for the PREDICTED proxy, BEFORE phase 1 (#25) | getPair(predicted proxy, WBNB) == 0x0: nobody pre-created it | deployer nonce=45, predicted proxy=0x48BD45D02641e688f63bD5129272C30A8828ad0b (nonce+1), predicted timelock=0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736 (nonce+3), getPair=0x0000000000000000000000000000000000000000 (2026-09-14 10:05 UTC) | - | PASS |
| H1.2a | Phase 1 SIMULATED (no broadcast) with the environment as it will be broadcast | exit 0; the script logs 'Migration treasury' AND 'Marketing wallet' as '(= predicted timelock)'; no override line, no marketing warning | exit=0; derived lines=2; override/warning lines=0; MARKETING_WALLET in env=no; TESTNET_TREASURY_OVERRIDE in env=no (2026-09-14 10:05 UTC) | - | PASS |
| H1.2 | Step 2, phase 1 broadcast: impl + proxy + migration, no env override | code at both; proxy == the predicted proxy; state file: treasuryOverridden=false AND marketingWalletOverridden=false; deployer nonce == expectedPhase2Nonce | token=0x48BD45D02641e688f63bD5129272C30A8828ad0b (code 262 ch), migration=0x9c54e19bad8AcA0b7910C0E88BfBcAAbB249B718 (code 6122 ch), proxy-as-predicted=True; treasuryOverridden=False, marketingWalletOverridden=False; nonce now=48, expectedPhase2Nonce=48 (2026-09-14 10:05 UTC) | journal broadcast/DeployPhase1.s.sol/97 | PASS |
| H1.3 | H0.1 on a public chain: token.marketingWallet(), migration.treasury(), migration.governance() from MINED state | all three == the predicted Timelock, which also == this runner's own nonce+3 computation (never typed anywhere) | token.marketingWallet=0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736, migration.treasury=0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736, migration.governance=0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736, state predictedTimelock=0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736, local nonce+3=0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736 (2026-09-14 10:05 UTC) | - | PASS |
| H1.3b | Supply placement and the fee model BETWEEN the phases | the full 1e30 in the Migration (fee-exempt); fees still the initialize() historical 10/20/20 -- phase 2 sets 10/10/20 | in migration=1000.0000 B (1000000000000000000000000000000 wei), migration fee-exempt=true, fees now=10/20/20 (2026-09-14 10:05 UTC) | - | PASS |

Phase 1 console, the completion block verbatim:

```
  === PHASE 1 complete ===
  DaimonV2 (proxy):      0x48BD45D02641e688f63bD5129272C30A8828ad0b
  DaimonMigration:       0x9c54e19bad8AcA0b7910C0E88BfBcAAbB249B718
  Timelock (predicted):  0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736
  Migration treasury:    0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736 (= predicted timelock)
  Marketing wallet:      0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736 (= predicted timelock)
  State file:            deployments/two-phase-97.json
```

State file after phase 1, verbatim:

```json
{
  "chainId": 97,
  "deployer": "0x052bB2834d292d078cf686F5f4BB2bb55E424943",
  "expectedPhase2Nonce": 48,
  "guardian": "0x4253f80666E48a04CAbE4966Aa63035Dbb4f104F",
  "marketingWallet": "0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736",
  "marketingWalletOverridden": false,
  "migration": "0x9c54e19bad8AcA0b7910C0E88BfBcAAbB249B718",
  "oldDaimon": "0xb0aA935f46354501d622C4A11a554CE226ADAE28",
  "predictedTimelock": "0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736",
  "router": "0xD99D1c33F9fC3444f8101754aBC46c52416550D1",
  "token": "0x48BD45D02641e688f63bD5129272C30A8828ad0b",
  "tokenImplementation": "0xD99Fa6935df427DB2Dc54050E37D5B99bba15Bc0",
  "treasury": "0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736",
  "treasuryOverridden": false
}
```

> From this row until phase 2 the deployer signs NOTHING: the Timelock must land at nonce 48.

### H1 (2, phase 2) -- Phase 2: the Timelock on the prediction, fees 10/10/20 set by the temporary role before the hand-over, one expiry on three contracts

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| H1.4.0 | The deployer's live nonce right before phase 2 | == expectedPhase2Nonce: nothing was signed between the phases | nonce=48, expected=48 (2026-09-14 10:05 UTC) | - | PASS |
| H1.4 | Phase 2 broadcast: timelock + staking + governor + wiring + renounce | the Timelock lands EXACTLY on the phase-1 prediction (the fourth fulfilment of one address: governance, treasury, marketing wallet, and now the contract itself) | timelock=0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736, predicted=0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736, match=True; staking=0xdB1C23eAAa306A7dbaD410E0aAa8eBDD249c62d1, governor=0x41F55DAc95A028c58Dd51FD72eec9101ed2DEd05 (2026-09-14 10:06 UTC) | journal broadcast/DeployPhase2.s.sol/97 | PASS |
| H1.5 | H0.2 on a public chain: the fees read from the live token right after phase 2, and who holds GOVERNANCE_ROLE now | 10/10/20, liquidityFee 30 (4% total from the first block); the Timelock holds the role, the deployer does not | taxFee=10 buybackFee=10 marketingFee=20 liquidityFee=30; hasRole(timelock)=true, hasRole(deployer)=false (2026-09-14 10:06 UTC) | - | PASS |
| H1.5b | The ORDER of setFees, grantRole(GOVERNANCE_ROLE, timelock), revokeRole(GOVERNANCE_ROLE, deployer) on the token | setFees BEFORE the grant BEFORE the revoke -- in the broadcast journal and on chain (block, index); all three status 0x1 | journal indices fees=12 grant=13 revoke=14; chain fees=(block 130963836, idx 3, 0x1) grant=(block 130963841, idx 2, 0x1) revoke=(block 130963845, idx 3, 0x1); setFees args=10,10,20 (2026-09-14 10:06 UTC) | 0xe8b739cdf68405568106ba40d5f92e6ab3819104a80e5602d7f9019237adf6f8 / 0x2421ff15ac9051b025515a26b255a9e789e21b244b3b149ae7059a877d11f5ea / 0x44a5c1bdebfffd4531bcec90dae846e44e019b4f33686ef60e3c19a890252a1f | PASS |
| H1.6 | The rest of the phase-2 configuration, live | share 1000; ONE expiry across the three contracts (exact); the whole supply in the migration; marketingWallet AND migration.treasury == the DEPLOYED timelock | share=1000; expiry token=1883988338 timelock=1883988338 governor=1883988338; supply=1000.0000 B in migration=1000.0000 B; marketingWallet=0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736, migration.treasury=0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736, timelock=0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736 (2026-09-14 10:06 UTC) | - | PASS |
| H1.6b | H1.3 of the plan: the guardian is the test Safe on all three contracts | GUARDIAN_ROLE on the token, CANCELLER_ROLE on the Timelock, governor.guardian() == the Safe | token hasRole=true, timelock canceller=true, governor.guardian=0x4253f80666E48a04CAbE4966Aa63035Dbb4f104F (Safe=0x4253f80666E48a04CAbE4966Aa63035Dbb4f104F) (2026-09-14 10:06 UTC) | - | PASS |

State file after phase 2 (the complete deployment record), verbatim:

```json
{
  "chainId": 97,
  "deployer": "0x052bB2834d292d078cf686F5f4BB2bb55E424943",
  "governor": "0x41F55DAc95A028c58Dd51FD72eec9101ed2DEd05",
  "guardian": "0x4253f80666E48a04CAbE4966Aa63035Dbb4f104F",
  "guardianAuthorityExpiry": 1883988338,
  "marketingWallet": "0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736",
  "marketingWalletOverridden": false,
  "migration": "0x9c54e19bad8AcA0b7910C0E88BfBcAAbB249B718",
  "oldDaimon": "0xb0aA935f46354501d622C4A11a554CE226ADAE28",
  "router": "0xD99D1c33F9fC3444f8101754aBC46c52416550D1",
  "staking": "0xdB1C23eAAa306A7dbaD410E0aAa8eBDD249c62d1",
  "timelock": "0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736",
  "token": "0x48BD45D02641e688f63bD5129272C30A8828ad0b",
  "tokenImplementation": "0xD99Fa6935df427DB2Dc54050E37D5B99bba15Bc0",
  "treasury": "0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736",
  "treasuryOverridden": false
}
```

### H1 (3-4) -- Step 3: the 36-check gate on Chapel; step 4: automation inert without reserves; the window closed to non-owners

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| H1.7 | Step 3: script/verify-deploy.ps1 -Rpc <chapel> (H0.3: 34 -> 36 checks) | 36/36 green, exit code 0 -- the MANDATORY GATE | exit=0; Post-broadcast verification -- chain 97 VERIFICATION PASSED: 36/36 checks green against live chain state. (2026-09-14 10:07 UTC) | - | PASS |

Full output of the verification, verbatim:

```
Post-broadcast verification -- chain 97
State file: C:\Users\Utente\Desktop\Daimon dao\deployments\two-phase-97.json


check                                                  expected                                   observed                                   verdict
-----                                                  --------                                   --------                                   -------
code at token                                          present                                    present                                    PASS
code at timelock                                       present                                    present                                    PASS
code at governor                                       present                                    present                                    PASS
code at staking                                        present                                    present                                    PASS
code at migration                                      present                                    present                                    PASS
token: timelock holds GOVERNANCE_ROLE                  true                                       true                                       PASS
token: deployer lacks GOVERNANCE_ROLE                  false                                      false                                      PASS
token: deployer lacks DEFAULT_ADMIN                    false                                      false                                      PASS
token: guardian holds GUARDIAN_ROLE                    true                                       true                                       PASS
token: stakingRewardShareBps == 1000                   1000                                       1000                                       PASS
token: stakingContract is the staking                  0xdB1C23eAAa306A7dbaD410E0aAa8eBDD249c62d1 0xdB1C23eAAa306A7dbaD410E0aAa8eBDD249c62d1 PASS
token: marketingWallet as configured                   0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736 0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736 PASS
token: migration is fee-exempt                         true                                       true                                       PASS
token: fees == (10,10,20)                              10,10,20                                   10,10,20                                   PASS
timelock: self-administers                             true                                       true                                       PASS
timelock: deployer lacks ADMIN_ROLE                    false                                      false                                      PASS
timelock: deployer lacks PROPOSER_ROLE                 false                                      false                                      PASS
timelock: deployer lacks EXECUTOR_ROLE                 false                                      false                                      PASS
timelock: governor is proposer                         true                                       true                                       PASS
timelock: governor is executor                         true                                       true                                       PASS
timelock: guardian is canceller                        true                                       true                                       PASS
timelock: governor is canceller                        true                                       true                                       PASS
timelock: self-cancel role present                     true                                       true                                       PASS
expiry: timelock == token (exact)                      1883988338                                 1883988338                                 PASS
expiry: governor == token (exact)                      1883988338                                 1883988338                                 PASS
staking: timelock is governance                        true                                       true                                       PASS
staking: deployer is not governance                    false                                      false                                      PASS
supply: totalSupply == INITIAL_SUPPLY                  1000000000000000000000000000000            1000000000000000000000000000000            PASS
supply: all of it in the migration                     1000000000000000000000000000000            1000000000000000000000000000000            PASS
migration: governance is the timelock                  0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736 0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736 PASS
migration: newDaimon is the token                      0x48BD45D02641e688f63bD5129272C30A8828ad0b 0x48BD45D02641e688f63bD5129272C30A8828ad0b PASS
migration: oldDaimon as configured                     0xb0aA935f46354501d622C4A11a554CE226ADAE28 0xb0aA935f46354501d622C4A11a554CE226ADAE28 PASS
migration: treasury as configured                      0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736 0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736 PASS
migration: treasury is the timelock                    0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736 0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736 PASS
token: marketingWallet is the deployed timelock (live) 0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736 0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736 PASS
token: pancake pair created                            present                                    present                                    PASS



Guardian expiry raw values: token=1883988338 timelock=1883988338 governor=1883988338
VERIFICATION PASSED: 36/36 checks green against live chain state.

```
| H1.8 | Step 4: automation state before liquidity (#27) | enabled by initialize, inert by construction: no inventory, reserves (0,0), pokes are the only trigger | swapAndLiquifyEnabled=true buyBackEnabled=true, inventory=0.0000 B, pair=0x82E71914ED2Ef364C6C760e3D728e6DC610FD2b8 reserves=(0,0) (2026-09-14 10:07 UTC) | - | PASS |
| H1.9 | A NON-owner (the holder, 5B DMX, not exempt) claims 1.00 B after the gate, BEFORE 11b | refused with AmountMismatch (#29): the treasury is not fee-exempt on the predecessor, the 11% fee breaks the 1:1 -- no claim is possible against this deployment yet; the approve itself is not gated | approve tx ok; claim: reverted with AmountMismatch; holder DMN=0 (2026-09-14 10:07 UTC) | 0x0d8463085e8dd52d87cd89dade40a03e4a8108737b369fc07c7af4b21585348f | PASS |

### H1 (5-8) -- Step 5a: the owner's exact claim; 5b: liquidity at the DMX price on the NET; 6: LP to the Timelock; 7: one pool; 8: reserves non-zero

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| H1.10 | Why the owner can claim before 11b: its status on the predecessor, read live | owner() == oldowner (cap-exempt as sender/recipient), excludedFromFee(oldowner) == true (no 11% on the claimant -> treasury leg); the treasury itself NOT exempt (11b not done), cap still 1.5B (11a not done) | owner=0xD7ca3011eB7Caae4A76c245c93FaAc56A7F58DaE, excludedFromFee(oldowner)=true, excludedFromFee(timelock)=false, maxTxAmount=1.5000 B (2026-09-14 10:07 UTC) | - | PASS |
| H1.11 | Sizing from live values, decision (c) on the maxTx finding: the largest single addLiquidityETH the token's maxTx allows, scaled to the tBNB oldowner holds; DMN leg derived from the price parameter 4.69e-10 BNB/token (read 2026-09-10 from the DMX pool) | cap: maxTxAmount gross -> net -> BNB leg at the price (mainnet: 5B gross, 4.8B net, 2.2512 BNB); BNB = min(cap leg, available - 0.03) rounded to 0.001; net DMN = BNB * 1e18 / 469000000; gross = ceil(net * 1000 / (1000 - taxFee - liquidityFee)) so the pair receives >= the net target by < 1000 wei; gross <= maxTxAmount (ONE addLiquidityETH, no exemption, no parameter change) | token maxTxAmount=5.0000 B -> cap net=4.8000 B -> cap BNB leg=2.2512 tBNB; available=0.2799 tBNB, used=0.2490 tBNB (LESS than the cap leg: Chapel scale, the ratio kept); fees=10/30 per mille; net target=0.5309 B (530916844349680170575692963 wei); gross=0.5530 B (553038379530916844349680170 wei); net of gross=530916844349680170575692964 wei (over target by 1 wei) (2026-09-14 10:07 UTC) | - | PASS |

> Decision (c), recorded: the initial liquidity is the largest single addLiquidityETH the 5B maxTx allows (5B gross, 4.8B net, BNB leg = 4.8B x 4.69e-10 = 2.2512 BNB on mainnet). No parameter change, no exemption to any person. Further depth comes from the treasury, which is maxTx-exempt through GOVERNANCE_ROLE (the Timelock holds every LP token from step 6 and adds liquidity by proposal). On Chapel the same ratio is scaled down to what oldowner holds; the price is the parameter, unchanged.
| H1.12 | Step 5a: oldowner claims EXACTLY the gross liquidity leg from the mock, before 11b | exact 1:1 on both legs: treasury (the Timelock) old +gross, oldowner DMN +gross, migratedAmount == gross -- possible only because the owner is fee-exempt and cap-exempt on the predecessor (H1.10) | treasury old +553038379530916844349680170 wei (0.5530 B), oldowner DMN +553038379530916844349680170 wei (0.5530 B), migratedAmount=553038379530916844349680170; gas=228807 (2026-09-14 10:07 UTC) | 0x41ddffd2ed7256398ad97685842fb8f90b893327f48ec64cad8ee4f54c3c629c | PASS |
| H1.13 | Step 5b: addLiquidityETH(gross DMN, 0.2490 tBNB) by oldowner -- BNB leg on the NET (#17) | reserve DMN == net of gross (exact), reserve BNB == the tBNB sent (no refund); oldowner DMN back to 0 (all of the claim went in); resulting price == the parameter within 1 ppm | BNB sent=249000000000000000 wei (0.2490); DMN gross=553038379530916844349680170 wei (0.5530 B); DMN received by the pair=530916844349680170575692964 wei (0.5309 B), expected net=530916844349680170575692964; reserve BNB=249000000000000000; price=468999999 wei/token vs parameter 469000000 (diff 1); oldowner DMN after=0; LP minted=11497751703836292291632; gas=377618 (2026-09-14 10:08 UTC) | 0xdba59f92a186c1f2083093e7de3a7a296e6d603bb88397a571ffdf564287993d / 0x843a9b068415001703df39f4d9fd67e1e2d23a58dd0e8955a0418393daf9eddb | PASS |
| H1.14 | Step 6: ALL the LP tokens, oldowner -> Timelock, one published transaction (H0.4) | from mined state: pair.balanceOf(oldowner) == 0, pair.balanceOf(deployer) == 0, pair.balanceOf(timelock) == totalSupply - MINIMUM_LIQUIDITY (1000 wei) | moved=11497751703836292291632 wei LP; oldowner LP=0, deployer LP=0, timelock LP=11497751703836292291632, totalSupply=11497751703836292292632, MINIMUM_LIQUIDITY=1000; gas=46822 (2026-09-14 10:08 UTC) | 0x828342616908adfe4375567537eded98947360b7a5512533ccf4a8a9ffeab87a | PASS |
| H1.15 | Step 7: the pair the token stores vs the pair the factory created | identical -- one pool | token.uniswapV2Pair=0x82E71914ED2Ef364C6C760e3D728e6DC610FD2b8, factory.getPair=0x82E71914ED2Ef364C6C760e3D728e6DC610FD2b8 (2026-09-14 10:08 UTC) | - | PASS |
| H1.16 | Step 8: both reserves non-zero | automation can now run on a real pool; the liquidity transfer itself was taxed: inventory == gross * liquidityFee / 1000 | DMN=0.5309 B, BNB=0.2490; inventory=16591243190610643385355953 wei (0.0165 B), expected 16591151385927505330490405 (2026-09-14 10:08 UTC) | - | DEVIATION |

> H1.16 is a DEVIATION row whose EXPECTATION was wrong, recorded as such (not rewritten): the observed inventory exceeds gross x 30/1000 by 91804683138054865548 wei (0.00055%). The token's fee inventory is a reflection-participating balance -- the contract excludes only the dead address and the pair from rewards (`_isExcludedFromReward`, DaimonV2.sol:400 and :437) -- so the taxed liquidity transfer credited the contract the 3% liquidityFee PLUS its pro-rata share of the 1% reflection: 16591151385927505330490405 x 5530383795309168443496801 / (totalSupply - pair balance) = 91804175153225202614 wei, the observed extra to within rate rounding. The step-8 facts asserted by the row hold (reserves 0.5309 B / 0.2490 tBNB, both non-zero). Day 0 asserted this inventory with `>=`; the H1f runner's two inventory rows (H1.18, H1.19) carried the same over-strict `==` and were corrected BEFORE running to "3% floored plus at most 0.01% of it", the corrected text being in the rows themselves. No contract behaviour involved; the reflection credit to the contract (and to the Migration, which is not excluded either) is the audited design.

### H1 (9-10) -- Step 9: the test sell pays 4%; step 10: the first poke -- zero BNB to the Timelock, the chunk/reserves ratio and the price move recorded

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| H1.17 | The campaign float: oldowner's SECOND claim, 7.00 B, separate from the liquidity claim of 5a | exact 1:1 again; harness necessity, recorded as such: steps 9 and 10 need DMN in non-owner hands and before 11b the owner is the only address that can claim -- on mainnet the volume that arms the first conversion is organic | treasury old +7.0000 B, oldowner DMN +7.0000 B (7000000000000000000000000000 wei) (2026-09-14 10:09 UTC) | 0x0daac69d570d51a79a9e1687e40557fadafee09dbabb1fff13cb4ddd495d9443 | NOTE |
| H1.18 | oldowner sends 0.50 B DMN to the stranger (an ordinary, taxed transfer) | the stranger receives 96% (+ its reflection share, < 0.01%); inventory += 3% (liquidityFee) plus the contract's own reflection share (< 0.01% of it) | stranger DMN=480002401286890092516638794 wei (96% = 480000000000000000000000000), inventory +15000158040912740287134773 wei (3% = 15000000000000000000000000, extra 158040912740287134773) (2026-09-14 10:09 UTC) | 0xc04721f048d04ef7c765fd080788962befcd4be0fe87e2c5e3e4fd796fd905db | PASS |
| H1.19 | Step 9: the stranger sells 0.05 B through the real router | the pair (reward-excluded) receives EXACTLY 96% of the amount sent (fee 4%), NOT 95%; inventory += 3% plus the contract's reflection share (< 0.01% of it); the seller receives BNB | pair DMN reserve +48000000000000000000000000 wei = 0.0480 B (96% would be 48000000000000000000000000, 95% would be 47500000000000000000000000); inventory +1500016555293031407234066 wei (3% = 1500000000000000000000000, extra 16555293031407234066); stranger BNB delta (gas included)=0.0205, BNB out of the pool=0.0206; sell gas=226811 (2026-09-14 10:09 UTC) | 0xef6c0a33bedae22d8dac9a07033209347403afb9ce54df8f93efcf84969f3f0d / 0x18c99f5a04b86c281a8d21d525fd07a0d04a268f1ae8e9d000c5ee9d041f101a | PASS |
| H1.20 | Did the router sell trigger any conversion? (#1) | no: router-initiated transfers skip the automation, inventory only grew, contract BNB zero, Timelock BNB zero | inventory 0.0315 B -> 0.0330 B, contract BNB=0.0000, timelock BNB=0.0000 (2026-09-14 10:09 UTC) | - | PASS |
| H1.21 | Inventory armed by ordinary transfers (3.50 B + 3.00 B oldowner -> holder, each under the token's maxTx) | inventory >= minimumTokensBeforeSwap; Timelock, staking and contract BNB all zero before the poke; reserves and price recorded before the poke | inventory=228103101012351284642331269 wei (0.2281 B) vs threshold 200000000000000000000000000 (0.2000 B); timelock BNB=0.0000, staking BNB=0.0000, contract BNB=0.0000; reserves before poke DMN=578916844349680170575692964 BNB=228392421478183778, price=394516801 wei/token (2026-09-14 10:10 UTC) | 0xe468104dc1d3180b82f23a2dc520f43fcdb8989fd5d2dbe29c4fffa2a9ef0b60 / 0x888f04ae0824d18abf86d5cd4f74557dcddb97ea1d18ee4b05408f3643aef9ab | PASS |
| H1.22 | Step 10: the stranger pokes (1 wei of DMN straight to the pair) | the call succeeds; exactly ONE threshold-sized chunk converts (#28 budget) | consumed=200000000000000000000000000 wei (0.2000 B) vs threshold 200000000000000000000000000; poke gas=305348, block 130964338 (2026-09-14 10:10 UTC) | 0x2faf97b988f45abce9ba47dd68e238c0d19cd9c8ce95bb2f910feb032348c9af | PASS |
| H1.23 | Where the BNB went, with stakingRewardShareBps == 1000 | the WHOLE marketing share (20/30 of the proceeds) to the staking pool, the buyback share retained by the token, and NO BNB from the token to the Timelock: the marketing-wallet branch is not entered (launch invariant) | received=58556378911911477 wei (0.0585 BNB): staking +0.0390 (expected 0.0390), contract +0.0195 (expected 0.0195), TIMELOCK +0 wei (2026-09-14 10:10 UTC) | - | PASS |
| H1.24 | THE NUMBER: the fee-swap chunk sold by the poke against the pool it was sold into | recorded, not judged here: chunk / DMN reserve before the poke; BNB drawn / BNB reserve; price before -> after and the move. This is what says whether 3 BNB is too thin on mainnet (the chunk is fixed: minimumTokensBeforeSwap = 0.02% of supply = 0.2 B) | chunk sold=0.2000 B against DMN reserve 0.5789 B = 3454 bps (34.54 %); BNB drawn=0.0585 of 0.2283 = 2563 bps; price 394516801 -> 218041301 wei/token, move -4473 bps (-44.73 %); reserves after DMN=778916844349680170575692964 BNB=169836042566272301; pool size: 0.2490 tBNB opened at 468999999 wei/token (2026-09-14 10:10 UTC) | 0x2faf97b988f45abce9ba47dd68e238c0d19cd9c8ce95bb2f910feb032348c9af | PASS |
| H1.25 | The marketing wallet (= the Timelock) after the first conversion on a public chain | zero DMN, zero BNB: it received nothing (the invariant, asserted after every send so far: 2 checks) | timelock DMN=0, timelock BNB=0 (2026-09-14 10:10 UTC) | - | PASS |

### H2 -- The 1.5B DMX cap binds claim() on Chapel: 3B refused before 11a, then 11a, then 11b last, then exact 1:1

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| H2.1 | Predecessor state: neither 11a nor 11b done | maxTxAmount == 1.50 B (the real DMX value); treasury NOT exempt; the holder is a plain holder (not the owner, not exempt) with 5.00 B | maxTxAmount=1.5000 B, excludedFromFee(timelock)=false, owner=0xD7ca3011eB7Caae4A76c245c93FaAc56A7F58DaE, holder old balance=5.0000 B, holder exempt=false (2026-09-14 10:10 UTC) | - | PASS |
| H2.2 | The holder claims 3.00 B (twice the cap) BEFORE 11a | REVERTS with the predecessor's own cap message: the cap is checked before the fee, so it is the cap -- not AmountMismatch -- that refuses | approve ok; claim: reverted (different reason): cast : Error: Failed to estimate gas: server returned an error response: error code 3: execution reverted: Transfer amount exceeds the maxTxAmount., data: "0x08 (2026-09-14 10:10 UTC) | 0x49470ac79852c78ee74975d66afb62cde24b348ef858559299360319e4aeb2cd | DEVIATION |
| H2.3 | State after the refused claim | nothing moved, nothing credited: treasury old delta 0, holder DMN delta 0, migratedAmount 0 | treasury old delta=0, holder DMN delta=0, migratedAmount=0 (2026-09-14 10:10 UTC) | - | PASS |
| H2.4 | Step 11a: setMaxTxAmount(1000.00 B) -- the holder first, then the owner | the holder is refused (onlyOwner); the owner's call is read back from the chain | holder: reverted (different reason): cast : Error: Failed to estimate gas: server returned an error response: error code 3: execution reverted: DMX: only owner, data: "0x08c379a00000000000000000000; owner: maxTxAmount 1.5000 B -> 1000.0000 B (2026-09-14 10:10 UTC) | 0xb019beb680918a0c93bd5ad0f566dc49da29480980b29e159f883e91f2922581 | PASS |
| H2.5 | Step 11b, LAST: excludeFromFee(TIMELOCK) on the predecessor -- the TREASURY, not the Migration | exemption active on the Timelock, none on the Migration: the migration window OPENS here | excludedFromFee(timelock)=true, excludedFromFee(migration)=false (2026-09-14 10:10 UTC) | 0xfcc95f7e6bc59236aabee96f515c57a1e6d7da05c14f29f34eef57767d29c13c | PASS |
| H2.6 | The holder repeats the SAME 3.00 B claim after 11a + 11b (the approve of H2.2 still stands) | passes: 1:1, no fee on either leg -- the treasury receives EXACTLY 3.00 B of mock DMX, the holder EXACTLY 3.00 B DMN, the holder's old balance down by exactly 3.00 B, migratedAmount 3.00 B | treasury old +3000000000000000000000000000 wei (3.0000 B), holder old -3.0000 B, holder DMN +3000000000000000000000000000 wei (3.0000 B), migratedAmount=3.0000 B; gas=171859 (2026-09-14 10:10 UTC) | 0x00e3be5ef104b43874182d870bba508cff9c1375596af995b1af7b5a153a0488 | PASS |
| H2.7 | The holder claims 1.00 B, below the (old) cap | identical to Level 2 P1.5.3: exact 1:1, migratedAmount accumulates to 4.00 B | treasury old +1.0000 B, holder DMN +1.0000 B (1000000000000000000000000000 wei), migratedAmount=4.0000 B; gas=154759 (2026-09-14 10:11 UTC) | 0x4ccbd8a351b2aee2aadb65d149019cc7994a6460b90f7b4d3e248abf0b756fd6 | PASS |
| H2.8 | The treasury (= the Timelock) through the day | old balance == totalMigrated (every claim of the day: the two owner claims and the holder's two); zero DMN, zero BNB | treasury old=11.5530 B (11553038379530916844349680170 wei), totalMigrated=11.5530 B (11553038379530916844349680170 wei); DMN=0, BNB=0.0000 (2026-09-14 10:11 UTC) | - | PASS |

> Launch order step 11a earning its place on a public chain: with the cap at its real value, a 3B claim is refused by the predecessor before any fee logic runs -- and with 11b deliberately done LAST, the window opened only after the cap was raised. Once raised, the same claim clears to the wei on both legs.

> H2.2 is a DEVIATION row whose expectation the chain MET: the observed column carries the predecessor's own message, `execution reverted: Transfer amount exceeds the maxTxAmount.`, returned at gas estimation (no transaction, no nonce moved -- H2.3 confirms nothing moved). The verdict is the harness matcher's: cast's stderr reaches PowerShell as ErrorRecords that Out-String wraps at the console width, and the phrase was split across two lines, so the exact-string match failed and the row fell to the `different reason` branch (H2.4's `DMX: only owner` shows the same wrapping, its verdict asked only for a revert). Fixed in `script/chapel2b/lib.ps1` (match on whitespace-flattened text) for the rows that follow; the H2.2 row is not rewritten and the claim is not replayed, since 11a has since raised the cap. Protocol behaviour exactly as expected: the cap refused a 3B claim before 11a.

### H3.1 -- The first mainnet proposal, rehearsed: propose setStakingRewardShareBps(600) -- one proposal, real clock

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| H3.1.1 | Launch state before the proposal | share 1000, marketing wallet == the Timelock (nothing to rotate: ONE proposal suffices), LP in the Timelock, Timelock BNB zero | share=1000, marketingWallet=0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736 (timelock=0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736), LP in timelock=11497751703836292291632, timelock BNB=0.0000, proposalThreshold=1000.0000 DMN of voting power (2026-09-14 10:11 UTC) | - | PASS |
| H3.1.2 | The holder stakes 1.00 B DMN on lock option 3 (365 days, 4.0x) | voting power == 4.00 B exactly (>= the threshold); totalVotingPower == the same (first and only staker) | votingPower=4.0000 B (4000000000000000000000000000 wei), totalVotingPower=4.0000 B; stake block 130964488, gas=529378 (2026-09-14 10:11 UTC) | 0x4449b98b8656389fd745ebc8ef3ab63c3f19cbcc3ef5532f270e3907bc61b74b / 0x7d3f8f8a7d230e2ca0837be931dfc4edc604c7de69a83dc0d0475426f4235ae2 | PASS |

> Harness error after H3.1.2, recorded in full. The first runner run signed the proposal (id 0, tx 0xe14495033a944a49d9fa309de3a8c4b2cea98915dc4ac09e88b6b0cd80bcc56b, block 130964516) and then died on a PowerShell reserved variable name (`$pid`) before logging it. That crash was misread as "nothing signed after the stake", and the runner was resumed at the propose step (`H3a-propose.ps1 -Resume`), which signed the SAME call again: proposal id 1, tx 0xf33f2dc4f2e53828d5da5708973930176786284e0972d7d9e3c7d4ca722b734c, block 130964768. The resumed run then failed on a read (`Prop-Field`, a local cast argument error not reproduced afterwards; the reader is hardened). Chain state is clean: two structurally identical, valid Pending proposals. The rows below are read from chain state by `H3a-finalize.ps1` (no signing): id 0 is THE campaign proposal, id 1 the duplicate, left to lapse. Lesson for the harness, applied: a runner must read proposalCount BEFORE and AFTER a propose and refuse to resume past a signed step.
| H3.1.3 | The proposal of the campaign: id 0, setStakingRewardShareBps(600) on the token, read back from chain state (the first runner run signed it, then crashed before this row) | state Pending; proposer == the holder; target == token, data == the calldata; snapshotBlock == propose block - 1; snapshotTotalVotingPower == 4.00 B; voteStart == block timestamp + 1 day; voteEnd - voteStart == 432000 s (5 days); quorum snapshot 1000 bps | id=0, state=Pending, proposer=0x583982463dA108879566868506Cba32E7b023576, target=0x48BD45D02641e688f63bD5129272C30A8828ad0b, data=0x6cf839b90000000000000000000000000000000000000000000000000000000000000258; propose block=130964516 ts=1789380691, snapshotBlock=130964515, snapshotTotalVotingPower=4.0000 B; voteStart=1789467091 (2026-09-15 10:11:31 UTC), voteEnd=1789899091 (2026-09-20 10:11:31 UTC), window=432000 s; quorumBpsSnapshot=1000 (2026-09-14 10:19 UTC) | 0xe14495033a944a49d9fa309de3a8c4b2cea98915dc4ac09e88b6b0cd80bcc56b | PASS |
| H3.1.4 | The DUPLICATE: id 1, the same call signed by the -Resume run on a wrong diagnosis (harness error, recorded not hidden) | structurally identical to id 0 and valid; it is NOT the campaign's proposal: nobody votes on it and it lapses to Defeated after its voteEnd -- a free extra observation (a proposal with no votes) on the real clock | id=1, state=Pending, proposer=0x583982463dA108879566868506Cba32E7b023576, data==id0 data=True; propose block=130964768, snapshotBlock=130964767, snapshotTotalVotingPower=4.0000 B; voteStart=2026-09-15 10:13:25 UTC, voteEnd=2026-09-20 10:13:25 UTC (2026-09-14 10:19 UTC) | 0xf33f2dc4f2e53828d5da5708973930176786284e0972d7d9e3c7d4ca722b734c | NOTE |

> Real-clock calendar for proposal 0 from here: voting opens at 2026-09-15 10:11:31 UTC (24 h after the propose block), closes at 2026-09-20 10:11:31 UTC (5 days later); queue any time after that arms the 7-day Timelock; the earliest execute, if queued at once, is 2026-09-27 10:11:31 UTC. H3.2-H3.5 and the H4 drill follow on that calendar. Proposal 1 is left untouched: its lapse to Defeated after 2026-09-20 10:13:25 UTC will be read and recorded. The monitor's expected URGENT on ProposalCreated (it touches stakingRewardShareBps) is to be confirmed by hand -- twice.

## Day 1 status (2026-09-14) -- Chapel, chain 97, everything below is on a public chain

**3 scenarios, 47 asserted rows: 43 PASS, 2 NOTE, 2 DEVIATION -- both
DEVIATION rows are harness-side (a wrong expectation, a wrong matcher),
each explained under its row; 0 protocol deviations.** Verification gate on
Chapel: **36/36**. The one script change between Day 0 and today (the
MARKETING_WALLET override refused on chain 56) is committed on its own,
before the broadcast, and neither override was set.

| scenario | rows | result |
|---|---|---|
| H1 -- launch order 1-10 on Chapel: mock by the owner, no pre-existing pair, phase 1 with the three predictions from mined state, phase 2 with setFees before the hand-over, 36/36, window closed to non-owners, the owner's exact claim, liquidity at the DMX price on the net, ALL LP to the Timelock, one pool, 4% test sell, first poke with zero BNB to the Timelock and the chunk/reserves ratio | 35 | 33 PASS, 1 NOTE (H1.17), 1 DEVIATION (H1.16, expectation) |
| H2 -- the 1.5B cap against claim() on a public chain: 3B refused before 11a, 11a, 11b LAST, the same 3B exact 1:1, 1B below the cap exact | 8 | 7 PASS, 1 DEVIATION (H2.2, matcher; the chain returned the expected message) |
| H3.1 -- the first mainnet proposal: setStakingRewardShareBps(600), one proposal intended, two created (harness), calendar recorded | 4 | 3 PASS, 1 NOTE (H3.1.4, the duplicate) |

### The numbers the day was run for

**Liquidity (decision (c), Chapel scale).** 0.2490 tBNB + 0.5530 B DMN
gross -> the pair received 0.5309 B net (exact to the wei, 1 wei over the
target); opening price 468999999 wei/token against the 469000000
parameter (4.69e-10 BNB/token); LP minted 11497751703836292291632 wei,
ALL of it to the Timelock in one published transaction (oldowner 0,
deployer 0, Timelock == totalSupply - 1000). Cap leg on mainnet at the
same price: 5 B gross, 4.8 B net, 2.2512 BNB.

**The first poke (H1.24).** The fee-swap chunk is fixed by the contract
(minimumTokensBeforeSwap = 0.02% of supply = 0.2 B), the pool is not:

| | Chapel today (observed) | mainnet at the (c) cap (arithmetic) | mainnet at 3 BNB (arithmetic, not reachable in one add) |
|---|---|---|---|
| DMN reserve before the poke | 0.5789 B | 4.8 B | 6.40 B |
| chunk / DMN reserve | 34.54% | 4.17% | 3.13% |
| BNB reserve | 0.2283 | 2.2512 | 3.0 |
| BNB drawn by the chunk | 0.0585 (25.63%) | ~0.0898 (~3.99%) | ~0.0901 (~3.00%) |
| price move of the one poke | -44.73% (394516801 -> 218041301 wei/token) | ~-7.8% | ~-5.9% |

The mainnet columns are constant-product arithmetic (0.25% pair fee) from
the observed chunk; the Chapel column is measured. Read: at the cap-sized
opening pool every threshold-sized conversion moves the price by about 8%,
at 3 BNB by about 6%; the chunk cannot be made smaller without a governance
call (setMinimumTokensBeforeSwap) and the pool cannot be made deeper by the
launch provider without breaking the maxTx. This is the operator's number.

**Where the first conversion's BNB went, share 1000:** received 0.0585 BNB:
staking +0.0390 (20/30, exact), token contract +0.0195 (buyback share,
exact), Timelock +0 wei. The Timelock's native balance is 0 at close.

**H2 on the real clock:** the 3B claim was refused by the predecessor's
own cap message with 11a and 11b both undone; 11a
(0xb019beb680918a0c93bd5ad0f566dc49da29480980b29e159f883e91f2922581) raised
the cap to 1000 B, 11b
(0xfcc95f7e6bc59236aabee96f515c57a1e6d7da05c14f29f34eef57767d29c13c) opened
the window LAST; the same 3B then cleared to the wei on both legs, and a 1B
claim below the old cap as at Level 2. Treasury old balance == totalMigrated
== 11.5530 B (the owner's two claims 0.5530 + 7.00, the holder's 3.00 +
1.00).

**H3.1:** proposal 0
(0xe14495033a944a49d9fa309de3a8c4b2cea98915dc4ac09e88b6b0cd80bcc56b, block
130964516, snapshot 130964515, snapshot voting power 4.00 B, quorum 1000
bps). Voting opens **2026-09-15 10:11:31 UTC**, closes **2026-09-20
10:11:31 UTC**; queue any time after; earliest execute **2026-09-27
10:11:31 UTC**. Proposal 1 (the duplicate) lapses after 2026-09-20 10:13:25
UTC and will be read then.

### Gate

- `git diff audit-final -- src/`: **empty** at every commit of the day.
- `forge test`: **187 passed, 0 failed, 0 skipped** (26 suites), run at close.
- Post-broadcast verification on Chapel: **36/36**, output verbatim under
  H1.7.
- The 2b invariant (the Timelock holds 0 native and 0 DMN) was asserted
  programmatically after every signed send once the Timelock existed:
  **21 checks**, reconstructed from the runners (H1c 1, H1d 1, H1e 4,
  H1f 7, H2 4, H3a 4) -- the state-file counter read 6 because every
  runner's final save wrote back the count it had loaded at its start;
  fixed in `Save-State` (the on-disk count wins) for the days that follow.
  Timelock at close: 0 BNB, 0 DMN, 11497751703836292291632 wei LP,
  11.5530 B mock DMX.

### Findings and deviations, recorded not hidden

1. **The 3-BNB opening liquidity does not fit the token's maxTx**
   (found before any transaction, decided by the operator): 3 BNB at
   4.69e-10 BNB/token is 6.40 B net, 6.66 B gross, above the 5 B
   maxTxAmount (0.5% of supply) that binds a non-exempt provider; a second
   router add would re-price on the gross (#17). **Decision (c)**: the
   initial liquidity is the largest single addLiquidityETH the cap allows
   (5 B gross, 4.8 B net, 2.2512 BNB), no parameter change, no exemption
   to any person; further depth comes from the treasury, which is
   maxTx-exempt through GOVERNANCE_ROLE and holds every LP token. Chapel
   ran the same ratio at the scale of the tBNB available (0.249). The
   checklist's step 5 has to say this; H5.4 work.
2. **H1.16 DEVIATION, expectation wrong:** the contract's fee inventory
   earns its own reflection share of the 1% tax (only the dead address and
   the pair are reward-excluded); the extra 91804683138054865548 wei is
   that share to within rounding. H1f's two inventory rows were corrected
   before running. Contract behaviour as audited.
3. **H2.2 DEVIATION, matcher wrong:** the chain returned "Transfer amount
   exceeds the maxTxAmount." and the harness missed it across a console
   line-wrap; fixed in the library. The claim cannot be replayed (11a has
   since raised the cap); the row stands with the message in its observed
   column.
4. **Two proposals instead of one (H3.1.4, NOTE):** the first H3a run
   signed proposal 0 and crashed on a PowerShell reserved name before
   logging it; the crash was misread as "nothing signed" and the resumed
   run signed proposal 1. Proposal 0 is the campaign's; proposal 1 is left
   to lapse and its Defeated state will be recorded. The runner now refuses
   to propose when the governor already holds a proposal. Second cause
   found the same hour: a runner's `$state` variable overwrote the
   library's `$script:STATE` path (case-insensitive names, the Level-2
   AddrBook lesson again); renamed to a name no scenario uses.
5. **H1.17 NOTE, the float claim:** steps 9-10 needed DMN in non-owner
   hands before 11b, and only the owner can claim then; on mainnet the
   volume that arms the first conversion is organic. The 7 B claim is
   exact 1:1 and part of the treasury's 11.5530 B.
6. **Chapel scale, not a defect:** the 0.048 B test sell moved the 0.53 B
   pool by 16% before the poke (394516801 wei/token at the poke, from
   468999999 at opening); the poke then moved it 44.73%. Both are the
   consequence of a 0.249 tBNB pool and are what the mainnet columns above
   scale from.
7. **Not run today, by the brief:** H1.6 (a second monitor instance in
   dry-run on the 2b contracts) and H5.4 (DEPLOY.md / CHECKLIST "36/36"
   from planned to effective, and the step-5 decision (c)). The July
   keystore `daimon-deployer2` does not decrypt with the shared password
   file and was not needed.

### Addresses at close (Chapel, chain 97, block 130965776), for the monitor

```
DaimonV2 (token/proxy):  0x48BD45D02641e688f63bD5129272C30A8828ad0b   fees 10/10/20, share 1000
DaimonV2 implementation: 0xD99Fa6935df427DB2Dc54050E37D5B99bba15Bc0
DaimonStaking:           0xdB1C23eAAa306A7dbaD410E0aAa8eBDD249c62d1   1 staker (holder), 4.00 B voting power, 0.0390 BNB rewards
DaimonGovernor:          0x41F55DAc95A028c58Dd51FD72eec9101ed2DEd05   proposal 0: Pending (campaign); proposal 1: Pending (duplicate, to lapse)
DaimonTimelock/treasury: 0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736   = marketing wallet; 0 BNB, 0 DMN, all LP, 11.5530 B mock DMX
DaimonMigration:         0x9c54e19bad8AcA0b7910C0E88BfBcAAbB249B718   totalMigrated 11.5530 B
Pair DMN/WBNB:           0x82E71914ED2Ef364C6C760e3D728e6DC610FD2b8   0.7789 B / 0.1698 tBNB, 218041301 wei/token
Mock predecessor (DMX):  0xb0aA935f46354501d622C4A11a554CE226ADAE28   owner = oldowner, cap 1000 B, Timelock exempt
Guardian (test Safe):    0x4253f80666E48a04CAbE4966Aa63035Dbb4f104F   GUARDIAN_ROLE, CANCELLER_ROLE, governor.guardian
Guardian expiry:         1883988338 (identical on the three contracts)
Roles: deployer 0x052bB2834d292d078cf686F5f4BB2bb55E424943 (0.0472 tBNB, nonce 64), oldowner 0xD7ca3011eB7Caae4A76c245c93FaAc56A7F58DaE (0.0307, 15),
       holder 0x583982463dA108879566868506Cba32E7b023576 (0.1118, 23), stranger 0x05Eb589Cba778FdFeE6bf2Dc0C1EFd32b48006e2 (0.1004, 7)
```

Gas of the day at 0.11 gwei: the two phases cost the deployer 0.0012 tBNB
(0.0484 -> 0.0472); oldowner spent 0.2490 in liquidity and 0.0003 in gas.

### What comes next, on the real clock

Days 2-6: H3.2 vote on proposal 0 (from 2026-09-15 10:11:31 UTC), the H4
guardian drill with the Safe and the stopwatch; day 6/7: queue, H4.7 in
parallel; day 13/14: execute (not before 2026-09-27 10:11:31 UTC), H3.4
poke that pays the marketing branch for the first time on a public chain,
H5 closure. The keystore password file is deleted at H5.5, after the
closing journal is pushed.

## Day 2 -- Vote (2026-09-15)

The governance cycle on the real clock, second sitting: the vote on
proposal 0. One signed transaction today (castVote by the holder), the
same harness and roles as Day 1, the same invariant asserted after the
send. Preflight is read from live state and refuses to loop: a Pending
proposal stops the runner with the seconds to voteStart. Proposal 1, the
duplicate, is read and left untouched.


### H3.2 -- The vote: the holder casts FOR on proposal 0; quorum from one staker; the duplicate receives nothing

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| H3.2.1 | Preflight from live state, before the vote | proposal 0 Active (voteStart <= now <= voteEnd); the holder's votingPowerAt(snapshot 130964515) == snapshotTotalVotingPower == totalVotingPowerAt(snapshot) == 4.00 B; quorum needed == 1000 bps of 4.00 B == 0.40 B; hasVoted false on 0 and 1; tallies 0/0/0 on both; proposal 1 Active too | block=131187872 ts=1789481203 (2026-09-15 14:06:43 UTC), voting open since 14112 s, closes in 417888 s; state0=Active, state1=Active; votingPowerAt(holder,130964515)=4.0000 B, totalVotingPowerAt(130964515)=4.0000 B, snapshotTotalVotingPower=4.0000 B, quorumBpsSnapshot=1000, quorumNeeded=0.4000 B (400000000000000000000000000 wei); hasVoted0=False hasVoted1=False; tally0 for/against/abstain=0/0/0, tally1=0/0/0 (2026-09-15 14:06 UTC) | - | PASS |
| H3.2.2 | The holder casts FOR (support 1) on proposal 0 | tx mined; hasVoted true; forVotes == votingPowerAt(holder, snapshot) == 4.00 B, against 0, abstain 0; state still Active (the window is open); ONE log: VoteCast(id 0, holder, 1, weight == forVotes) from the governor; quorum For+Abstain >= 0.40 B; For > Against | block=131187896 ts=1789481213 (2026-09-15 14:06:53 UTC), gas=87520; state=Active, hasVoted=True; for/against/abstain=4.0000 B/0/0 (for=4000000000000000000000000000 wei); VoteCast decoded: emitter=0x41f55dac95a028c58dd51fd72eec9101ed2ded05, id=0, voter=0x583982463da108879566868506cba32e7b023576, support=1, weight=4.0000 B (4000000000000000000000000000 wei); logs in receipt=1; quorum: For+Abstain=4.0000 B vs needed 0.4000 B = 1000 % of the bar (2026-09-15 14:06 UTC) | 0xdec995de5fb825affd6eadf99f2259039d433d22451bab5370d3dd58b89f2a8a | PASS |
| H3.2.3 | Proposal 1 (the duplicate) after the vote, read only | untouched: hasVoted false, tallies 0/0/0, still Active; it lapses to Defeated after 2026-09-20 10:13:25 UTC (quorum 0 < 0.40 B) | state1=Active, hasVoted1=False, for/against/abstain=0/0/0 (2026-09-15 14:07 UTC) | - | PASS |

> Calendar: proposal 0 stays Active until voteEnd 1789899091 (2026-09-20 10:11:31 UTC); from then state() reads Succeeded (quorum 4.0000 B >= 0.4000 B, For 4.0000 B > Against 0) and queue() arms the 7-day Timelock; earliest execute if queued at once 2026-09-27 10:11:31 UTC. Proposal 1 lapses to Defeated after 2026-09-20 10:13:25 UTC and is read then. Nothing else is signed today.
