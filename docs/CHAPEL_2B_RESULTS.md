# Chapel "2b" mini-campaign -- results (branch chapel/level-2b)

**Status: CLOSED (2026-09-28)** -- see "Campaign closure" at the end.
Day 0 is local (Anvil forking BSC Chapel); Days 1-9 (2026-09-14 to
2026-09-28) are on BSC Chapel, the governance cycle on the real clock.

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

## Days 3-4 -- Guardian drill (2026-09-16/17)

H4.1, H4.2 and H4.4 of the drill kit (`script/chapel2b/DRILL_KIT.md`,
commit e4b422f): four Safe transactions, all four `setPaused` on the token,
signed by the guardians through the Safe web interface with their Ledgers.
The harness signs nothing for the Safe, by design, so this entry is written
READ-ONLY from mined state: every receipt (status, block, logs) re-read
with cast, every derived claim below -- who signed, what was scheduled,
where the deadline moved -- computed from those receipts and from live
calls. The campaign RPC (publicnode) served the four TRANSACTIONS but
returned null for their RECEIPTS (load-balanced backends prune, the
monitor's history lesson again); the receipts here come from the archival
endpoint `data-seed-prebsc-1-s1.bnbchain.org:8545` (T1 cross-checked
identical on `-2-s1`), the live reads from the campaign RPC. The times
noted in the group during the drill (18:00:10, 21:48:31, 14:39:19,
15:05:26) run 13-17 s AFTER the mined timestamps; the chain's are recorded.
Rule H4.8 was applied aloud on every confirmation.

The signers, as the drill names them and as the chain identifies them (the
executor is `tx.from`; the co-signer is recovered from the ECDSA entry in
the `signatures` field over the safeTxHash the Safe logged in
`ExecutionSuccess`; the four transactions are the Safe's first four,
nonces 0-3):

| signer | address |
|---|---|
| F1 (Psy) | `0xD9dB15E21836789a2CB9AfFe6EEbe2454162fc16` |
| F2 | `0xdFfeAEb85Bb580641351649D4AD4ce0C6ABf687f` |
| F3 | `0xacA4FaA9A0CB89749ad8CB4383EF8c3AE1530F9b` |

### H4.1 -- Pause: F1 proposes, F2 confirms and executes -- the first setPaused(true) ever mined on this deployment

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| H4.1.1 | T1: `setPaused(true)` through the Safe -- status, target, calldata, Safe nonce, all from mined state | status 0x1; `to` == the Safe; inner call == kit row 2a: the token, value 0, `0x16c38b3c...01`, operation CALL; the Safe's FIRST transaction (nonce 0), threshold 2 | status=0x1, block=131410964, ts=1789581597 (2026-09-16 17:59:57 UTC), gas=164551; to=0x4253f80666E48a04CAbE4966Aa63035Dbb4f104F, inner target=0x48BD45D02641e688f63bD5129272C30A8828ad0b, data=0x16c38b3c...0001 (== kit 2a "setPaused(true)"), operation=0, Safe nonce=0, threshold=2 (SafeMultiSigTransaction) (2026-09-17 20:25 UTC) | 0x0c54e11750bcc957d65cafefbf5fa382a438b3ff779b7c48105ccb10b27aeb3d | PASS |
| H4.1.2 | The events of T1 | `PausedSet(true)` + `PauseScheduled(until)` from the TOKEN (the sentinel's URGENT pair), `ExecutionSuccess` from the SAFE | PausedSet(true); PauseScheduled(until=1790791197 = 2026-09-30 17:59:57 UTC), until - ts = 1209600 s EXACTLY (+14 days, the #36 window; the guardianExpiry clamp not reached); ExecutionSuccess(safeTxHash=0xa176a7077358ba27ffe5716e6aa7617152aefcaff13935fb7600d402d1039066, payment=0) | - | PASS |
| H4.1.3 | The choreography, from the signature bytes | exactly TWO entries in `signatures` (130 bytes); the ECDSA one recovers to F1 over the safeTxHash (the proposer); the pre-validated one (v=1) is the executor == tx.from == F2 | ECDSA(v=27): ecrecover(safeTxHash) = 0xD9dB15E21836789a2CB9AfFe6EEbe2454162fc16 (F1); pre-validated = 0xdFfeAEb85Bb580641351649D4AD4ce0C6ABf687f (F2) = tx.from | - | PASS |

### H4.2 -- Unpause: F3 proposes, F1 confirms -- the window closed early, 3 h 48 m into its 14 days

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| H4.2.1 | T2: `setPaused(false)` through the Safe | status 0x1; inner call == kit 2a "setPaused(false)"; Safe nonce 1; mined INSIDE T1's window (an early unpause, the only kind the drill runs: a lapse is H4.3, not run by the 28/08 decision) | status=0x1, block=131441401, ts=1789595294 (2026-09-16 21:48:14 UTC), gas=77887; inner target=the token, data=0x16c38b3c...0000, Safe nonce=1; 13697 s (3 h 48 m 17 s) after T1, with 1195903 s (13 d 20 h 11 m 43 s) of scheduled window unused (2026-09-17 20:25 UTC) | 0x5590d2bb4b0120108d7203c058ba04386f57907daa3cb4b2718ba323d383c67b | PASS |
| H4.2.2 | The events of T2 | `PausedSet(false)` from the token and NO `PauseScheduled` (an unpause schedules nothing); `ExecutionSuccess` from the Safe | PausedSet(false); token logs in receipt=1 (no PauseScheduled); ExecutionSuccess(safeTxHash=0x78744755a7e24dc31409c4807232126f7ccb2da132b96d7c30fdb8f58e3ebb17, payment=0) | - | PASS |
| H4.2.3 | The choreography, from the signature bytes | ECDSA recovers to F3 (the proposer); executor == tx.from == F1 | ECDSA(v=27): ecrecover(safeTxHash) = 0xacA4FaA9A0CB89749ad8CB4383EF8c3AE1530F9b (F3); pre-validated = 0xD9dB15E21836789a2CB9AfFe6EEbe2454162fc16 (F1) = tx.from | - | PASS |

### H4.4 -- "Psy unreachable": pause and unpause by F2 and F3 alone -- F1's key appears in neither transaction

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| H4.4.1 | T3: `setPaused(true)`, the second pause, with F1 out of the loop | status 0x1; inner call == kit 2a "setPaused(true)"; Safe nonce 2 | status=0x1, block=131576184, ts=1789655946 (2026-09-17 14:39:06 UTC), gas=113259; inner target=the token, data=0x16c38b3c...0001, Safe nonce=2 (2026-09-17 20:25 UTC) | 0x09480f2d85b29a40d1768b129204c1b6f69dd02e21c0e52c621d9e63a2d57f5d | PASS |
| H4.4.2 | The events of T3 | `PausedSet(true)` + `PauseScheduled(until)` again at +14 days exactly; `ExecutionSuccess` | PausedSet(true); PauseScheduled(until=1790865546 = 2026-10-01 14:39:06 UTC), until - ts = 1209600 s EXACTLY, second time to the second; ExecutionSuccess(safeTxHash=0x5347388a4864b4d8834a7bedb3a9445f787004aa0ec1bf5fed3ab650653982ec, payment=0) | - | PASS |
| H4.4.3 | T3 choreography | ECDSA recovers to F2 (the proposer); executor == tx.from == F3; F1 nowhere | ECDSA(v=27): ecrecover(safeTxHash) = 0xdFfeAEb85Bb580641351649D4AD4ce0C6ABf687f (F2); pre-validated = 0xacA4FaA9A0CB89749ad8CB4383EF8c3AE1530F9b (F3) = tx.from | - | PASS |
| H4.4.4 | T4: `setPaused(false)`, closing the second window | status 0x1; inner call == kit 2a "setPaused(false)"; Safe nonce 3; `PausedSet(false)`, no `PauseScheduled`, `ExecutionSuccess` | status=0x1, block=131579664, ts=1789657513 (2026-09-17 15:05:13 UTC), gas=77875; data=0x16c38b3c...0000, Safe nonce=3; 1567 s (26 m 07 s) after T3, 1208033 s (13 d 23 h 33 m 53 s) of window unused; PausedSet(false); ExecutionSuccess(safeTxHash=0x00f16f9b45400d3d2264ef680955e49ecb7f92b6e28ab99824d60503970dd1c3, payment=0) (2026-09-17 20:25 UTC) | 0x91ab55323130c3c3c8fc700542f6a7b1ed41cb9295403a22382e47b1bed67e67 | PASS |
| H4.4.5 | T4 choreography, and the point of the drill | ECDSA recovers to F3 (the proposer); executor == tx.from == F2; across T3 AND T4 the address of F1 appears in NO field: not tx.from, not in the signature bytes | ECDSA(v=27): ecrecover(safeTxHash) = 0xacA4FaA9A0CB89749ad8CB4383EF8c3AE1530F9b (F3); pre-validated = 0xdFfeAEb85Bb580641351649D4AD4ce0C6ABf687f (F2) = tx.from; 0xD9dB15E2...fc16 absent from both transactions' inputs and logs | - | PASS |

> The point, observed on chain: between 14:39:06 and 15:05:13 UTC on
> 2026-09-17 the guardian paused and unpaused the token with F1 absent --
> four signature entries across the two transactions, none of them F1's.
> The 2-of-3 works with the operator entirely out of the loop, which is
> what the mandate is for.

### The pause credit and the migration deadline, read live (block 131622352, 2026-09-17 20:25:23 UTC)

| read | expected | observed | verdict |
|---|---|---|---|
| token `isPaused()` / `paused` / `pauseUntil` | false / false / 0 -- both windows closed early by their unpauses | false / false / 0 | PASS |
| token `cumulativePauseSeconds` | the UNION of the two scheduled windows, not their sum: 1209600 (T1's full window) + 74349 (T3's window outruns the first window's accounted end by T3 - T1 = 74349 s; `_pauseAccountedUntil` prevents the double count, DaimonV2.sol setPaused) = 1283949 | 1283949 (14 d 20 h 39 m 09 s) | PASS |
| migration `effectiveMigrationDeadline()` | the kit's preparation base 1791972340 (2026-10-14 10:05:40 UTC) + cumulativePauseSeconds = 1793256289 | 1793256289 = **2026-10-29 06:44:49 UTC** | PASS |

> Audit finding #36, observed on a public chain: each 2b pause
> self-scheduled its own end at +14 days TO THE SECOND (1790791197 =
> T1 + 1209600, 1790865546 = T3 + 1209600), needing no second call to end;
> the early unpauses clawed nothing back; and the double-count guard meant
> the second pause credited only the 20 h 39 m 09 s by which its window
> outran the first. Net: the effective migration deadline moved 2026-10-14
> -> 2026-10-29, +14 d 20 h 39 m 09 s of credit for 4 h 14 m 24 s of
> actual pause. The kit predicted "~14 days" for the first pair alone: it
> held, and the second pair cost the deadline only its overhang.

### Findings of the drill, recorded not fixed

1. **The Safe interface reported failure for transactions that succeeded
   on chain.** On BNB Chain testnet the Safe web app returned HTTP 422 and
   showed as "failed" transactions the chain had mined with status 0x1 --
   all four above are status 0x1 with `ExecutionSuccess` in the logs. The
   chain (and the monitor) is the only source of truth; the interface is a
   convenience. Rule H4.8's premise in practice: what gets read aloud
   before confirming is the calldata, and what settles "did it work" is
   the receipt, never the web app's verdict.
2. **MetaMask signs only with the account of the physically connected
   Ledger.** With a different account selected in MetaMask than the Ledger
   actually plugged in, signing fails with "does not belong to the
   connected device". The fix at the desk is selecting the matching
   account, not reconnecting the device. For the mainnet runbook.
3. **A queued Safe transaction disappears from the other signers' view
   once an execution attempt is made** -- including an attempt the
   interface itself reports as failed (finding 1). Coordination has to
   assume the executor sees state the others no longer do: the group
   announces execution attempts aloud, and the result is confirmed from
   the chain, not from the queue view. For the mainnet runbook.

**3 scenarios plus the live accounting, 14 asserted rows: 14 PASS, 0 NOTE,
0 DEVIATION.** The harness signed nothing; the four transactions are the
Safe's, nonces 0-3, 433572 gas in total at 0.1 gwei. `git diff audit-final
-- src/` stays empty (this entry only READS `setPaused`).

What remains of H4, on the calendar: H4.3 (a pause left to lapse) is not
run on the real clock, by the 2026-08-28 decision -- the self-termination
is the E2 reference, and #36's scheduling side is now observed above.
H4.5-H4.7 run on the P-A/P-B calendar: voting on ids 2 and 3 opened
2026-09-16 22:54 UTC and closes 2026-09-21 22:54 UTC; the proposers' own
FOR votes (1.20 B each against the 0.64 B quorum) must land in that window
for the queue drills, then anyone queues after voteEnd and the Safe cancels
inside the 7 days, stopwatch from `CallScheduled` to `Cancelled`.
Proposal 0 is unchanged (Succeeded expected 2026-09-20 10:11:31 UTC,
earliest execute 2026-09-27 10:11:31 UTC).

## Day 5 -- Drill proposals voted (2026-09-17)

The prerequisite of the queue-side cancel drills (H4.5-H4.7), run inside
the P-A/P-B voting window: each proposer casts its own FOR on its OWN
proposal and on nothing else -- staker3 on id 2 (P-A, hostile), staker1
on id 3 (P-B, harmless). The holder votes on NEITHER: it is the
campaign's voter on proposal 0, and Scenario W requires the hostile
proposal to pass without the team voting. Two signed transactions, the
same harness and invariant as every day before; keystores were checked
against the kit's proposer addresses before anything was signed.


### D5 -- The proposers' own FOR votes on P-A (id 2) and P-B (id 3); quorum from one voter each; the holder abstains by design

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| D5.1 | Preflight from live state, before the votes | both proposals Active (voteStart <= now <= voteEnd); proposer fields == the kit's staker3/staker1; snapshots == kit (131258242 / 131258303); snapshotTotalVotingPower == 6.40 B, quorumBps 1000, quorum needed == 0.64 B; votingPowerAt(proposer, snapshot) == 1.20 B >= quorum; hasVoted false everywhere it must be (each proposer on both ids, the holder on 2 and 3); tallies 0/0/0 on both; proposal 0 exactly as Day 2 left it (Active, 4.00 B / 0 / 0, holder hasVoted true) | block=131628154 ts=1789679334 (2026-09-17 21:08:54 UTC); P-A: state=Active, proposer=0xbb843DFe3dec6D7dFc4Ef194A1a9BDc7A07eac84, snap=131258242, window 2026-09-16 22:54:30..2026-09-21 22:54:30, weight=1.2000 B, tally=0/0/0, hvSelf=False hvHolder=False; P-B: state=Active, proposer=0xfbcE9e13C309549c82B0775C8587E3470f2837b0, snap=131258303, window 2026-09-16 22:54:58..2026-09-21 22:54:58, weight=1.2000 B, tally=0/0/0, hvSelf=False hvHolder=False; cross staker3-on-3=False staker1-on-2=False; snapTvp=6.4000 B/6.4000 B, quorumNeeded=0.6400 B; proposal 0: state=Active, tally=4.0000 B/0/0, holderVoted=True (2026-09-17 21:09 UTC) | - | PASS |
| D5.2 | staker3 casts FOR (support 1) on proposal 2 (P-A: hostile, setMaxTxAmount(type(uint256).max)) | tx mined; hasVoted true; forVotes == votingPowerAt(proposer, snapshot 131258242) == 1.20 B, against 0, abstain 0; state still Active (the window is open); ONE log: VoteCast(id 2, proposer, 1, weight == forVotes) from the governor; quorum For+Abstain >= 0.64 B; For > Against | block=131628191 ts=1789679350 (2026-09-17 21:09:10 UTC), gas=87532; state=Active, hasVoted=True; for/against/abstain=1.2000 B/0/0 (for=1200000000000000000000000000 wei); VoteCast decoded (receipt from bsc-testnet.publicnode.com): emitter=0x41f55dac95a028c58dd51fd72eec9101ed2ded05, id=2, voter=0xbb843dfe3dec6d7dfc4ef194a1a9bdc7a07eac84, support=1, weight=1.2000 B (1200000000000000000000000000 wei); logs in receipt=1; quorum: For+Abstain=1.2000 B vs needed 0.6400 B = 187 % of the bar (2026-09-17 21:09 UTC) | 0x554119c24d898f716e4253ab34008236df68011292c46e6a1cbdb5aa2a75b9e3 | PASS |
| D5.3 | staker1 casts FOR (support 1) on proposal 3 (P-B: harmless, setMaxSwapSlippageBps(500) no-op) | tx mined; hasVoted true; forVotes == votingPowerAt(proposer, snapshot 131258303) == 1.20 B, against 0, abstain 0; state still Active (the window is open); ONE log: VoteCast(id 3, proposer, 1, weight == forVotes) from the governor; quorum For+Abstain >= 0.64 B; For > Against | block=131628206 ts=1789679357 (2026-09-17 21:09:17 UTC), gas=87532; state=Active, hasVoted=True; for/against/abstain=1.2000 B/0/0 (for=1200000000000000000000000000 wei); VoteCast decoded (receipt from bsc-testnet.publicnode.com): emitter=0x41f55dac95a028c58dd51fd72eec9101ed2ded05, id=3, voter=0xfbce9e13c309549c82b0775c8587e3470f2837b0, support=1, weight=1.2000 B (1200000000000000000000000000 wei); logs in receipt=1; quorum: For+Abstain=1.2000 B vs needed 0.6400 B = 187 % of the bar (2026-09-17 21:09 UTC) | 0xcd88ca5dcd971d9ec7e56ef70d0c00f59af52f4b055246beaeca1545a16ca980 | PASS |
| D5.4 | Proposal 0 and the deliberate non-votes, after both sends, read only | proposal 0 untouched: still Active, tally 4.00 B / 0 / 0, neither staker has voted on it; the holder has voted on NEITHER drill proposal (Scenario W discipline) | state0=Active, tally0=4.0000 B/0/0; hasVoted(0, staker3)=False, hasVoted(0, staker1)=False; hasVoted(2, holder)=False, hasVoted(3, holder)=False (2026-09-17 21:09 UTC) | - | PASS |

> Queueable-from timestamps, read from mined state: P-A (id 2) voteEnd 1790031270 = 2026-09-21 22:54:30 UTC, P-B (id 3) voteEnd 1790031298 = 2026-09-21 22:54:58 UTC. From those instants state() reads Succeeded (each 1.20 B FOR clears the 0.64 B quorum alone) and anyone may call queue(id); the 7-day Timelock then puts earliest execute at 2026-09-28 22:54:30 UTC / 2026-09-28 22:54:58 UTC, and the Safe cancels inside that window (H4.5 on P-B via the Governor, H4.6/H4.7 on P-A direct at the Timelock), stopwatch from CallScheduled to Cancelled. Proposal 0 runs its own calendar: Succeeded expected 2026-09-20 10:11:31 UTC. Nothing else is signed today.

## Day 6 -- Queue (2026-09-21)

The governance cycle on the real clock, third sitting: the queue of
proposal 0. Voting closed at voteEnd and the clock, not a transaction,
moved the proposal to Succeeded; today queue(0) hands the operation to
the Timelock and the 7-day delay starts its real clock. One signed
transaction (queue by the holder, the proposer), the same harness and
roles as Day 1, the same invariant asserted after the send. Preflight is
read from live state and refuses to loop: any state but Succeeded stops
the runner before anything is signed. Proposal 1, the duplicate that
received no vote, is read as Defeated and left untouched; P-A/P-B are
read and left to their own calendar.


### H3.3a -- The queue: the holder queues proposal 0; the Timelock takes the operation with the 7-day floor; the duplicate lapsed to Defeated on its own

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| H3.3a.1 | Preflight from live state: proposal 0, before the queue | chain 97; proposalCount 4; state Succeeded (now > voteEnd == Day 1's voteEnd); tally 4.00 B / 0 / 0 == Day 2's VoteCast weight; quorum For+Abstain >= 0.40 B and For > Against; queued=executed=canceled=false; data == setStakingRewardShareBps(600); target == token; value 0; proposer == holder, who has voted | chain=97, block=132351017 ts=1790004879 (2026-09-21 15:34:39 UTC), proposalCount=4; state0=Succeeded, voteEnd=1789899091 (2026-09-20 10:11:31 UTC), closed since 105788 s; for/against/abstain=4.0000 B/0/0 (for=4000000000000000000000000000 wei), quorumNeeded=0.4000 B, quorum 1000 % of the bar; queued=false executed=false canceled=false; calldataMatch=True, target=0x48BD45D02641e688f63bD5129272C30A8828ad0b, value=0, proposer=0x583982463dA108879566868506Cba32E7b023576, holderVoted=True, snapshot=130964515, salt=0xc338b2d3b7beef85b7a81b6ca2d1d84fd054e7162f433debfdc3528e6d3a30a0 (2026-09-21 15:34 UTC) | - | PASS |
| H3.3a.2 | Proposal 1 (the duplicate) after its voteEnd, read only -- recorded, not acted on | Defeated by the clock alone: no vote ever cast (hasVoted false, tally 0/0/0, quorum 0 < 0.40 B); same calldata, target and quorum bar as proposal 0; queued=executed=canceled=false; now > its voteEnd 2026-09-20 10:13:25 UTC | state1=Defeated, voteEnd=1789899205 (2026-09-20 10:13:25 UTC), lapsed since 105674 s; for/against/abstain=0/0/0, quorumNeeded=0.4000 B, holderVoted=False; queued=false executed=false canceled=false; sameCalldata=True, snapshot=130964767 (2026-09-21 15:34 UTC) | - | PASS |
| H3.3a.3 | Preflight from live state: the Timelock before queue (pending operations: 0, proven from storage) | getMinDelay == MIN_DELAY == 604800; governor holds PROPOSER_ROLE (the only scheduling path, and it schedules only from queue: no proposal has queued=true); operation id (target, 0, data, predecessor 0x0, salt) computed on-chain == local keccak; its slot empty (readyTimestamp 0); CallScheduled events over the RPC's readable range: 0; P-A/P-B still Active, not queued | getMinDelay=604800, MIN_DELAY=604800, governorIsProposer=true, opId=0x37dfdc53dc643b59a0b35a54da5b8430ab82e9641615733ce3ce71e6862c5033, localMatch=True, slot readyTimestamp=0 executed=false canceled=false; CallScheduled count=0 (readable from block 132263606 to 132351017; 26 pruned chunks below it); state2=Active queued2=false, state3=Active queued3=false (2026-09-21 15:34 UTC) | - | PASS |
| H3.3a.4 | The holder (the proposer) calls queue(0) | receipt status 1, from == holder, to == governor; proposal queued flag true; state() == Queued (4); executed/canceled untouched; tally unchanged | status=0x1, from=0x583982463da108879566868506cba32e7b023576, to=0x41f55dac95a028c58dd51fd72eec9101ed2ded05, block=132351061 (ts=1790004899 = 2026-09-21 15:34:59 UTC), gas=114598; queued=true executed=false canceled=false, state=Queued (4); tally=4.0000 B/0/0; receipt served by bsc-testnet.publicnode.com (2026-09-21 15:35 UTC) | 0x6deb52a33ec8d8ad2e6995196ecf0716cc88acc7681a70df8c0c831b9af0b076 | PASS |
| H3.3a.5 | operations(opId) read back from the Timelock | readyTimestamp == queue-block timestamp + 604800 EXACTLY (7 real days); executed=false; canceled=false | readyTimestamp=1790609699 (2026-09-28 15:34:59 UTC), queue block ts=1790004899, delta=604800 s, executed=false, canceled=false (2026-09-21 15:35 UTC) | - | PASS |
| H3.3a.6 | The two events decoded from the receipt | exactly 2 logs: CallScheduled(id == opId, target == token, value 0, data == setStakingRewardShareBps(600), delay 604800) from the timelock; ProposalQueued(id=0, eta == readyTimestamp) from the governor | logs=2 (receipt from bsc-testnet.publicnode.com); CallScheduled id=0x37dfdc53dc643b59a0b35a54da5b8430ab82e9641615733ce3ce71e6862c5033 target=0x48bd45d02641e688f63bd5129272c30a8828ad0b value=0 delay=604800 dataMatch=True; ProposalQueued id=0 eta=1790609699 (2026-09-28 15:34:59 UTC) (2026-09-21 15:35 UTC) | 0x6deb52a33ec8d8ad2e6995196ecf0716cc88acc7681a70df8c0c831b9af0b076 | PASS |
| H3.3a.7 | The stranger tries queue(0) again | refused: ProposalAlreadyQueued -- the Governor rejects it itself, before the Timelock's OperationAlreadyScheduled; no transaction mined | reverted with ProposalAlreadyQueued (2026-09-21 15:35 UTC) | - | PASS |
| H3.3a.8 | The holder tries execute(0) inside the delay | refused: TooEarly from the Timelock (state is Queued, so the Governor lets the call reach the Timelock, which holds the clock); no transaction mined | reverted with TooEarly (2026-09-21 15:35 UTC) | - | PASS |
| H3.3a.9 | Read back over eth_getLogs: ProposalQueued on the governor, CallScheduled on the timelock | exactly 1 each -- today's queue, the first operation this Timelock has ever scheduled | ProposalQueued found=1, CallScheduled found=1 (blocks 132351017-132351077, unreadable chunks=0/0) (2026-09-21 15:35 UTC) | - | PASS |

> Earliest execute, read from the Timelock's storage: readyTimestamp 1790609699 = 2026-09-28 15:34:59 UTC (queue block 132351061 at 1790004899 + 604800 s). execute(0) before that instant reverts TooEarly (H3.3a.8); from that instant anyone may call it, and the H3.3b/H3.4 sitting (execute, then the first poke that pays the marketing branch on a public chain) is planned for day 13/14, not before 2026-09-28 15:34:59 UTC. The Safe (CANCELLER) can cancel the operation at any point inside the delay -- it will not: proposal 0 is the campaign's own. Wallet choice, recorded as an assumption: the holder (the proposer) signed, as the July campaign and Level 2 queued from the proposer; queue() is permissionless and every value verified above is sender-independent. Proposal 1 stays Defeated forever (no path out of that state); nothing is ever signed for it. P-A (id 2) and P-B (id 3) close at 2026-09-21 22:54:30 / 2026-09-21 22:54:58 UTC and belong to the H4.5-H4.7 drills. Nothing else is signed today.

## Day 7 -- Drill proposals queued (2026-09-21)

The last prerequisite of the queue-side cancel drills (H4.5-H4.7): the
two throwaway proposals go into the Timelock. Their voting closed at
22:54:30 / 22:54:58 UTC on the 21st and the clock alone moved P-A (id 2,
hostile) and P-B (id 3, harmless) to Succeeded, each on its proposer's
own 1.20 B FOR. Today queue(2) and queue(3) schedule the two operations
and start a 7-day delay on each; the Safe's signers then cancel inside
that window, separately, with their own keys (P-B through the Governor,
P-A direct at the Timelock). Nothing is canceled here and proposal 0 is
not touched: its operation from Day 6 is read before and after and must
not move. Two signed transactions from the holder (queue() is
permissionless; every value below is sender-independent), the same
harness and invariant as every day before. Preflight is read from live
state and refuses to loop: any state but Succeeded on either drill
proposal stops the runner before anything is signed.


### D7 -- The drill queues: the holder queues P-A (id 2) and P-B (id 3); the Timelock takes both operations with the 7-day floor; the ids match the kit; proposal 0 untouched

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| D7.1 | Preflight from live state: the chain, proposal 0, the duplicate, the Timelock roles | chain 97; proposalCount 4; proposal 0 Queued (queued=true, executed=canceled=false) with its operation's readyTimestamp == Day 6's 1790609699 and executed=canceled=false; proposal 1 Defeated; getMinDelay 604800; governor holds PROPOSER_ROLE; the Safe holds CANCELLER_ROLE and is the Governor's guardian (the two cancel paths the drills will use) | chain=97, block=132415055 ts=1790033697 (2026-09-21 23:34:57 UTC), proposalCount=4; state0=Queued queued0=true executed0=false canceled0=false, op0 readyTimestamp=1790609699 (2026-09-28 15:34:59 UTC) executed=false canceled=false; state1=Defeated; getMinDelay=604800, governorIsProposer=true, safeIsCanceller=true, governor.guardian=0x4253f80666E48a04CAbE4966Aa63035Dbb4f104F (2026-09-21 23:35 UTC) | - | PASS |
| D7.2 | Preflight from live state: P-A (id 2, hostile, setMaxTxAmount(type(uint256).max)), before the queue | state Succeeded (now > voteEnd == kit == Day 5's record); snapshot == kit; proposer == staker3; target == token, value 0, data == kit calldata, timelockSalt == kit; tally 1.20 B / 0 / 0 == Day 5's VoteCast weight; quorum For+Abstain >= 0.64 B and For > Against; proposer has voted, the holder has not; queued=executed=canceled=false; opId: Timelock.hashOperation == local keccak == the kit's precomputed value; its slot empty (readyTimestamp 0) | state=Succeeded, voteEnd=1790031270 (2026-09-21 22:54:30 UTC), closed since 2427 s; snapshot=131258242, proposer=0xbb843DFe3dec6D7dFc4Ef194A1a9BDc7A07eac84, target=0x48BD45D02641e688f63bD5129272C30A8828ad0b, value=0, dataMatch=True, saltMatch=True; for/against/abstain=1.2000 B/0/0, quorumNeeded=0.6400 B, quorum 187 % of the bar, proposerVoted=True holderVoted=False; queued=false executed=false canceled=false; opId chain=0xd895606ccce44f00f6ca3af8a1fa99e6e1dbcf2221fd7b6b3ab50a39d9398e7d local=0xd895606ccce44f00f6ca3af8a1fa99e6e1dbcf2221fd7b6b3ab50a39d9398e7d kit=0xd895606ccce44f00f6ca3af8a1fa99e6e1dbcf2221fd7b6b3ab50a39d9398e7d allMatch=True; slot readyTimestamp=0 executed=false canceled=false (2026-09-21 23:35 UTC) | - | PASS |
| D7.3 | Preflight from live state: P-B (id 3, harmless, setMaxSwapSlippageBps(500) no-op), before the queue | state Succeeded (now > voteEnd == kit == Day 5's record); snapshot == kit; proposer == staker1; target == token, value 0, data == kit calldata, timelockSalt == kit; tally 1.20 B / 0 / 0 == Day 5's VoteCast weight; quorum For+Abstain >= 0.64 B and For > Against; proposer has voted, the holder has not; queued=executed=canceled=false; opId: Timelock.hashOperation == local keccak == the kit's precomputed value; its slot empty (readyTimestamp 0) | state=Succeeded, voteEnd=1790031298 (2026-09-21 22:54:58 UTC), closed since 2399 s; snapshot=131258303, proposer=0xfbcE9e13C309549c82B0775C8587E3470f2837b0, target=0x48BD45D02641e688f63bD5129272C30A8828ad0b, value=0, dataMatch=True, saltMatch=True; for/against/abstain=1.2000 B/0/0, quorumNeeded=0.6400 B, quorum 187 % of the bar, proposerVoted=True holderVoted=False; queued=false executed=false canceled=false; opId chain=0x86564200b67e9203c71e7eb160f7e5afdc016d7f632d18daf803800bfd0ccb12 local=0x86564200b67e9203c71e7eb160f7e5afdc016d7f632d18daf803800bfd0ccb12 kit=0x86564200b67e9203c71e7eb160f7e5afdc016d7f632d18daf803800bfd0ccb12 allMatch=True; slot readyTimestamp=0 executed=false canceled=false (2026-09-21 23:35 UTC) | - | PASS |
| D7.4 | The holder calls queue(2) -- P-A | receipt status 1, from == holder, to == governor; proposal queued flag true; state() == Queued (4); executed/canceled untouched; tally unchanged | status=0x1, from=0x583982463da108879566868506cba32e7b023576, to=0x41f55dac95a028c58dd51fd72eec9101ed2ded05, block=132415086 (ts=1790033711 = 2026-09-21 23:35:11 UTC), gas=114610; queued=true executed=false canceled=false, state=Queued (4); tally=1.2000 B/0/0; receipt served by bsc-testnet.publicnode.com (2026-09-21 23:35 UTC) | 0xd5c55796602e25206221b4aa82b86d8154045e5d73f59242c560332ccd1f84b9 | PASS |
| D7.5 | operations(opId) read back from the Timelock -- P-A, opId == the kit's | readyTimestamp == queue-block timestamp + 604800 EXACTLY (7 real days); executed=false; canceled=false | opId=0xd895606ccce44f00f6ca3af8a1fa99e6e1dbcf2221fd7b6b3ab50a39d9398e7d; readyTimestamp=1790638511 (2026-09-28 23:35:11 UTC), queue block ts=1790033711, delta=604800 s, executed=false, canceled=false (2026-09-21 23:35 UTC) | - | PASS |
| D7.6 | The two events decoded from the receipt -- P-A | exactly 2 logs: CallScheduled(id == the kit's opId, target == token, value 0, data == the kit's calldata, delay 604800) from the timelock; ProposalQueued(id=2, eta == readyTimestamp) from the governor. This is the CallScheduled the kit (2c) waits for before the Timelock cancel row may be signed | logs=2 (receipt from bsc-testnet.publicnode.com); CallScheduled id=0xd895606ccce44f00f6ca3af8a1fa99e6e1dbcf2221fd7b6b3ab50a39d9398e7d target=0x48bd45d02641e688f63bd5129272c30a8828ad0b value=0 delay=604800 dataMatch=True; ProposalQueued id=2 eta=1790638511 (2026-09-28 23:35:11 UTC) (2026-09-21 23:35 UTC) | 0xd5c55796602e25206221b4aa82b86d8154045e5d73f59242c560332ccd1f84b9 | PASS |
| D7.7 | The holder calls queue(3) -- P-B | receipt status 1, from == holder, to == governor; proposal queued flag true; state() == Queued (4); executed/canceled untouched; tally unchanged | status=0x1, from=0x583982463da108879566868506cba32e7b023576, to=0x41f55dac95a028c58dd51fd72eec9101ed2ded05, block=132415101 (ts=1790033717 = 2026-09-21 23:35:17 UTC), gas=114610; queued=true executed=false canceled=false, state=Queued (4); tally=1.2000 B/0/0; receipt served by bsc-testnet.publicnode.com (2026-09-21 23:35 UTC) | 0x50dfe2ba19b52201416eaa9a2d067cd0c44a4f1205c007d6c9ee65d04904b194 | PASS |
| D7.8 | operations(opId) read back from the Timelock -- P-B, opId == the kit's | readyTimestamp == queue-block timestamp + 604800 EXACTLY (7 real days); executed=false; canceled=false | opId=0x86564200b67e9203c71e7eb160f7e5afdc016d7f632d18daf803800bfd0ccb12; readyTimestamp=1790638517 (2026-09-28 23:35:17 UTC), queue block ts=1790033717, delta=604800 s, executed=false, canceled=false (2026-09-21 23:35 UTC) | - | PASS |
| D7.9 | The two events decoded from the receipt -- P-B | exactly 2 logs: CallScheduled(id == the kit's opId, target == token, value 0, data == the kit's calldata, delay 604800) from the timelock; ProposalQueued(id=3, eta == readyTimestamp) from the governor. This is the CallScheduled the kit (2c) waits for before the Timelock cancel row may be signed | logs=2 (receipt from bsc-testnet.publicnode.com); CallScheduled id=0x86564200b67e9203c71e7eb160f7e5afdc016d7f632d18daf803800bfd0ccb12 target=0x48bd45d02641e688f63bd5129272c30a8828ad0b value=0 delay=604800 dataMatch=True; ProposalQueued id=3 eta=1790638517 (2026-09-28 23:35:17 UTC) (2026-09-21 23:35 UTC) | 0x50dfe2ba19b52201416eaa9a2d067cd0c44a4f1205c007d6c9ee65d04904b194 | PASS |
| D7.10 | The stranger tries queue(2) again -- P-A | refused: ProposalAlreadyQueued -- the Governor rejects it itself, before the Timelock's OperationAlreadyScheduled; no transaction mined | reverted with ProposalAlreadyQueued (2026-09-21 23:35 UTC) | - | PASS |
| D7.11 | The stranger tries queue(3) again -- P-B | refused: ProposalAlreadyQueued -- the Governor rejects it itself, before the Timelock's OperationAlreadyScheduled; no transaction mined | reverted with ProposalAlreadyQueued (2026-09-21 23:35 UTC) | - | PASS |
| D7.12 | Proposal 0 after both sends, read only | untouched: still Queued, queued=true, executed=canceled=false, tally 4.00 B / 0 / 0; its operation's readyTimestamp still 1790609699 (2026-09-28 15:34:59 UTC), executed=canceled=false | state0=Queued queued=true executed=false canceled=false, tally=4.0000 B/0/0; op0 readyTimestamp=1790609699 (2026-09-28 15:34:59 UTC) executed=false canceled=false (2026-09-21 23:35 UTC) | - | PASS |
| D7.13 | Read back over eth_getLogs: ProposalQueued on the governor, CallScheduled on the timelock, since the preflight block | exactly 2 each -- today's two queues; with Day 6's this Timelock now carries three scheduled operations, all pending | ProposalQueued found=2, CallScheduled found=2 (blocks 132415055-132415117, unreadable chunks=0/0) (2026-09-21 23:35 UTC) | - | PASS |

> Cancel windows, read from the Timelock's storage. P-A (id 2, hostile): opId 0xd895606ccce44f00f6ca3af8a1fa99e6e1dbcf2221fd7b6b3ab50a39d9398e7d, CallScheduled in block 132415086 at 1790033711 (2026-09-21 23:35:11 UTC), readyTimestamp 1790638511 = 2026-09-28 23:35:11 UTC; the guardian may cancel from now until that instant, 7d 23h 59m 46s at the time of this note (2026-09-21 23:35:25 UTC); planned path H4.6/H4.7 -- Timelock.cancel(opId) direct by the Safe, then Governor.state(2) must read Canceled on its own. P-B (id 3, harmless): opId 0x86564200b67e9203c71e7eb160f7e5afdc016d7f632d18daf803800bfd0ccb12, CallScheduled in block 132415101 at 1790033717 (2026-09-21 23:35:17 UTC), readyTimestamp 1790638517 = 2026-09-28 23:35:17 UTC; the guardian may cancel from now until that instant, 7d 23h 59m 52s at the time of this note; planned path H4.5 -- Governor.cancel(3) by the Safe, the atomic cross-cancel of the Timelock operation. Both opIds equal the values precomputed in DRILL_KIT.md 2c, so the Safe rows written on 2026-09-15 are valid as printed: target the Timelock 0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736 with calldata 0xc4d252f5 + opId for P-A, target the Governor 0x41F55DAc95A028c58Dd51FD72eec9101ed2DEd05 with 0x40e58ee5 + id for P-B; the kit's condition for signing the Timelock row (CallScheduled seen) is met by D7.6/D7.9. The stopwatch of each drill runs from the CallScheduled timestamp above to the Cancelled block. If the Safe does NOT cancel before readyTimestamp, execute(id) becomes possible for anyone: for P-B a no-op, for P-A the removal of the per-transfer cap on the drill deployment -- the whole point of the drill is that it never gets there. Nothing is canceled by this harness; the cancellations are the signers' work, in the Safe, with the H4.8 read-aloud. Proposal 0 (the campaign's own) is untouched, earliest execute unchanged at 2026-09-28 15:34:59 UTC. Wallet choice, recorded as an assumption: the holder signed both queues, as on Day 6; queue() is permissionless and every value verified above is sender-independent. Nothing else is signed today.

## Day 8 -- Guardian cancellations (H4.5, H4.6, H4.7) (2026-09-22)

The queue-side half of the drill kit (`script/chapel2b/DRILL_KIT.md` 2b/2c):
two Safe transactions, signed by the guardians through the Safe web
interface with their Ledgers, inside the 7-day windows Day 7 opened. T5
cancels P-B (id 3, harmless) THROUGH the Governor -- the atomic
cross-cancel; T6 cancels P-A (id 2, hostile) DIRECTLY at the Timelock,
bypassing the Governor -- the independent guardian path, and then the
Governor must agree on its own. The harness signs nothing for the Safe,
by design, so this entry is written READ-ONLY from mined state, as Days
3-4 were: every receipt re-read with cast, every derived claim -- who
signed, what was cancelled, how far into the delay -- computed from the
receipts and from live calls. This time the campaign RPC (publicnode)
served both RECEIPTS; each was re-read from the archival endpoint
`data-seed-prebsc-1-s1.bnbchain.org:8545` and the two copies are
identical in every field that matters (status, block, hash, from, to,
gasUsed, index, the logs). The signers are as in the Days 3-4 table (F1
`0xD9dB...fc16`, F2 `0xdFfe...687f`, F3 `0xacA4...0F9b`); the executor is
`tx.from`, the co-signer is recovered from the ECDSA entry in
`signatures` over the safeTxHash the Safe logged in `ExecutionSuccess`
(the hash itself recomputed with `Safe.getTransactionHash` at the logged
nonce; the recovery is a static call to the ecrecover precompile). The
two transactions are the Safe's fifth and sixth, nonces 4 and 5. Rule
H4.8 was applied aloud on both confirmations. Live reads at block
132591687, 2026-09-22 21:39:43 UTC, unless noted.

### H4.5 -- P-B cancelled through the Governor: F1 proposes, F3 confirms and executes -- ProposalCanceled(3) and the Timelock's Cancelled in ONE transaction

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| H4.5.1 | T5: `Governor.cancel(3)` through the Safe -- status, target, calldata, Safe nonce, all from mined state | status 0x1; `to` == the Safe; inner call == kit row 2b for P-B: the GOVERNOR, value 0, `0x40e58ee5...03`, operation CALL; Safe nonce 4 (the fifth transaction), threshold 2; mined INSIDE P-B's window (before readyTimestamp 1790638517) | status=0x1, block=132589551, ts=1790112222 (2026-09-22 21:23:42 UTC), txIndex=0, gas=122800; to=0x4253f80666E48a04CAbE4966Aa63035Dbb4f104F, inner target=0x41F55DAc95A028c58Dd51FD72eec9101ed2DEd05 (the Governor), data=0x40e58ee5...0003 (== kit 2b "P-B, id 3"), operation=0, safeTxGas=baseGas=gasPrice=0, Safe nonce=4, threshold=2 (SafeMultiSigTransaction additionalInfo); F3's EOA nonce 1 (2026-09-22 21:39 UTC) | 0x56babddceabcb341dae31c79c003554f983095ea9d57c670e89564636c6466d2 | PASS |
| H4.5.2 | The events of T5 -- the atomic cross-cancel (#26) | exactly 4 logs: `SafeMultiSigTransaction` (Safe), `Cancelled(id == P-B opId)` from the TIMELOCK, `ProposalCanceled(3)` from the GOVERNOR, `ExecutionSuccess` (Safe) -- the Timelock's cancel and the Governor's flag in the SAME transaction, the Timelock's first (the Governor cancels the operation, then marks itself) | logs=4; logIndex 0 SafeMultiSigTransaction (0x4253...104F); logIndex 1 Cancelled(id=0x86564200b67e9203c71e7eb160f7e5afdc016d7f632d18daf803800bfd0ccb12) from 0xd8e8...9736 (the Timelock); logIndex 2 ProposalCanceled(id=3) from 0x41f5...ded05 (the Governor); logIndex 3 ExecutionSuccess(safeTxHash=0x4b6d40c1c2ea9490d64c8dccbaffbb3400f6d115db5ce01dec885f15372870ee, payment=0); opId == Day 7's D7.8 == the kit's | - | PASS |
| H4.5.3 | The choreography, from the signature bytes | exactly TWO entries in `signatures` (130 bytes), sorted by owner address; the ECDSA one recovers to F1 over the safeTxHash (the proposer); the pre-validated one (v=1) is the executor == tx.from == F3; the logged safeTxHash == `getTransactionHash(...)` at nonce 4; `checkNSignatures` accepts the bytes as F3 and refuses them as F2 | 130 bytes; entry 0 pre-validated (v=1) = 0xacA4FaA9A0CB89749ad8CB4383EF8c3AE1530F9b (F3) = tx.from; entry 1 ECDSA (v=27): ecrecover(safeTxHash) = 0xD9dB15E21836789a2CB9AfFe6EEbe2454162fc16 (F1); getTransactionHash(nonce 4) = 0x4b6d40c1...70ee == logged; checkNSignatures(hash, data, sigs, 2) static: as F3 -> accepted (empty return), as F2 -> GS025 | - | PASS |
| H4.5.4 | The stopwatch: `CallScheduled` (Day 7, D7.9) to `Cancelled` | inside the delay, with margin before readyTimestamp 1790638517 | CallScheduled ts=1790033717 (2026-09-21 23:35:17 UTC) -> Cancelled ts=1790112222 (2026-09-22 21:23:42 UTC) = 78505 s (21 h 48 m 25 s) into the delay; 526295 s (6 d 02 h 11 m 35 s) of window unused before readyTimestamp 2026-09-28 23:35:17 UTC | - | PASS |

### H4.6 -- P-A cancelled directly at the Timelock: F3 proposes, F1 confirms and executes -- the Governor is never called

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| H4.6.1 | T6: `Timelock.cancel(opId)` through the Safe -- status, target, calldata, Safe nonce, all from mined state | status 0x1; `to` == the Safe; inner call == kit row 2c for P-A: the TIMELOCK, value 0, `0xc4d252f5` + opId 0xd895606c...98e7d, operation CALL; Safe nonce 5 (the sixth transaction), threshold 2; mined INSIDE P-A's window (before readyTimestamp 1790638511) | status=0x1, block=132590593, ts=1790112691 (2026-09-22 21:31:31 UTC), txIndex=2, gas=92861; to=0x4253f80666E48a04CAbE4966Aa63035Dbb4f104F, inner target=0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736 (the Timelock), data=0xc4d252f5d895606ccce44f00f6ca3af8a1fa99e6e1dbcf2221fd7b6b3ab50a39d9398e7d (== kit 2c "P-A, id 2"), operation=0, safeTxGas=baseGas=gasPrice=0, Safe nonce=5, threshold=2; F1's EOA nonce 4; 469 s (7 m 49 s) after T5 (2026-09-22 21:39 UTC) | 0x160c72eaabb0ac38c0edd46a76dd3bd56de8c5e0b0df36f5d8b277624844a82d | PASS |
| H4.6.2 | The events of T6 -- the Governor absent | exactly 3 logs: `SafeMultiSigTransaction` (Safe), `Cancelled(id == P-A opId)` from the TIMELOCK, `ExecutionSuccess` (Safe); NO log from the Governor (0x41F5...DEd05 emits nothing: it was never called) | logs=3; logIndex 2 SafeMultiSigTransaction; logIndex 3 Cancelled(id=0xd895606ccce44f00f6ca3af8a1fa99e6e1dbcf2221fd7b6b3ab50a39d9398e7d) from 0xd8e8...9736 (the Timelock); logIndex 4 ExecutionSuccess(safeTxHash=0x302aa1544c6d8c2f46141ecac874842cec5db664b5d7c40701a0bbf25f3811f4, payment=0); Governor logs in receipt=0; opId == Day 7's D7.5 == the kit's | - | PASS |
| H4.6.3 | The choreography, from the signature bytes | ECDSA recovers to F3 (the proposer); executor == tx.from == F1; the logged safeTxHash == `getTransactionHash(...)` at nonce 5; `checkNSignatures` accepts the bytes as F1 | 130 bytes; entry 0 ECDSA (v=28): ecrecover(safeTxHash) = 0xacA4FaA9A0CB89749ad8CB4383EF8c3AE1530F9b (F3); entry 1 pre-validated (v=1) = 0xD9dB15E21836789a2CB9AfFe6EEbe2454162fc16 (F1) = tx.from; getTransactionHash(nonce 5) = 0x302aa154...11f4 == logged; checkNSignatures static as F1 -> accepted (empty return) | - | PASS |
| H4.6.4 | The stopwatch: `CallScheduled` (Day 7, D7.6) to `Cancelled` | inside the delay, with margin before readyTimestamp 1790638511 | CallScheduled ts=1790033711 (2026-09-21 23:35:11 UTC) -> Cancelled ts=1790112691 (2026-09-22 21:31:31 UTC) = 78980 s (21 h 56 m 20 s) into the delay; 525820 s (6 d 02 h 03 m 40 s) of window unused before readyTimestamp 2026-09-28 23:35:11 UTC | - | PASS |

### H4.7 -- The point of the drill: Governor.state(2) reads Canceled on its own; neither operation can ever execute

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| H4.7.1 | `Governor.state(2)` live, the Governor having NEVER been called for P-A | the raw word 6 = `ProposalState.Canceled` (enum Pending 0, Active 1, Defeated 2, Succeeded 3, Queued 4, Executed 5, Canceled 6) | raw=0x0000000000000000000000000000000000000000000000000000000000000006 -> uint8 6 = **Canceled** (block 132591687, 2026-09-22 21:39:43 UTC) | - | PASS |
| H4.7.2 | `proposals(2)` -- the struct behind that answer | the Governor's OWN flags untouched: canceled=false, executed=false, queued=true (nothing in the Governor was written by T6); state() reaches Canceled through the `p.queued` branch (#26): `timelock.operations(timelock.hashOperation(target, value, data, 0x0, timelockSalt)).canceled == true`; hashOperation re-derived on chain from the struct == the kit's opId | canceled=**false** executed=false queued=**true**; target=0x48BD...ad0b, value=0, data=0xec28438a + ffff...ffff (setMaxTxAmount(type(uint256).max), == kit), timelockSalt=0x58a832d2ab8d15f59c6f9093ab4d93ab2d3a6df30f1d19a0efc3b11163972250; tally 1.20 B/0/0 unchanged; hashOperation(struct) = 0xd895606ccce44f00f6ca3af8a1fa99e6e1dbcf2221fd7b6b3ab50a39d9398e7d == kit; operations(opId).canceled = true -> state() = Canceled | - | PASS |
| H4.7.3 | `Governor.state(3)` and `proposals(3)` -- the other path, for contrast | raw 6 = Canceled as well, but here the Governor's own flag IS set: canceled=true (written by T5's `cancel(3)`), executed=false, queued=true. Two paths, one answer | state(3) raw=0x...06 -> 6 = Canceled; proposals(3): canceled=**true** executed=false queued=true; data=0xe89d59de...01f4 (setMaxSwapSlippageBps(500), == kit), timelockSalt=0xbece6405b58ad27650973b1ef8a096dde74dd496c2574ff41914cb6b0c181213; tally 1.20 B/0/0 unchanged | - | PASS |
| H4.7.4 | `Timelock.operations(opId)` for both drill operations | canceled=true, executed=false on both; readyTimestamp UNTOUCHED by the cancel (the slot keeps its schedule, only the flag flips: 1790638511 / 1790638517) | P-A 0xd895606c...98e7d: readyTimestamp=1790638511 (2026-09-28 23:35:11 UTC) executed=false canceled=**true**; P-B 0x86564200...ccb12: readyTimestamp=1790638517 (2026-09-28 23:35:17 UTC) executed=false canceled=**true** | - | PASS |
| H4.7.5 | Static execute attempts, both contracts, both operations -- nothing sent, the exact revert recorded | `Timelock.execute(target, 0, data, 0x0, salt)` as the Governor (the EXECUTOR): `OperationNotReady()` -- the `readyTimestamp == 0 \|\| canceled` gate, and it will still revert after 2026-09-28 (the gate precedes the clock check); as the Safe: `AccessControlUnauthorizedAccount(safe, EXECUTOR_ROLE)` -- the guardian cannot execute anything; `Governor.execute(2)` / `execute(3)` by anyone: `ProposalNotSucceeded()` -- state() is Canceled, neither Succeeded nor Queued | Timelock.execute(P-A) from the Governor -> reverted 0xf800799b = OperationNotReady(); Timelock.execute(P-B) from the Governor -> 0xf800799b = OperationNotReady(); Timelock.execute(P-A) from the Safe -> 0xe2517d3f = AccessControlUnauthorizedAccount(0x4253...104F, 0xd8aa0f31...9e63 = EXECUTOR_ROLE); Governor.execute(2) from F1 -> 0xfeace5cd = ProposalNotSucceeded(); Governor.execute(3) from F1 -> 0xfeace5cd = ProposalNotSucceeded() | - | PASS |
| H4.7.6 | Double cancels and the convergence path, static -- nothing sent | `Timelock.cancel(opId)` again by the Safe: `OperationAlreadyCanceled()` on both; `Governor.cancel(3)` again by the Safe: `ProposalAlreadyCanceled()`; `Governor.cancel(2)` by the Safe WOULD succeed (the struct's flag is still false, the Timelock's is true: the `if (!opCanceled)` branch skips the re-cancel and only converges the flag) -- read, recorded, NOT sent: state(2) already answers Canceled without it | Timelock.cancel(P-A) from the Safe -> 0xe5aa780e = OperationAlreadyCanceled(); Timelock.cancel(P-B) -> 0xe5aa780e = OperationAlreadyCanceled(); Governor.cancel(3) from the Safe -> 0x7fe099a0 = ProposalAlreadyCanceled(); Governor.cancel(2) from the Safe -> returns 0x (would succeed), not sent | - | PASS |
| H4.7.7 | What P-A wanted to change, read live | `maxTxAmount` still 5 B (0.5 % of supply): the per-transfer cap the hostile proposal would have removed is intact; the token's roles unchanged; not paused | maxTxAmount=5000000000000000000000000000 (5.0000 B); isPaused=false, cumulativePauseSeconds=1283949 (== Days 3-4); token: timelock GOVERNANCE_ROLE=true, safe GUARDIAN_ROLE=true, safe GOVERNANCE_ROLE=false, safe DEFAULT_ADMIN=false | - | PASS |

### Untouched by the day, read live

| step | read | expected | observed | verdict |
|---|---|---|---|---|
| U8.1 | Proposal 0 (the campaign's own) | still Queued (4); struct queued=true, executed=canceled=false; tally 4.00 B / 0 / 0; its operation's readyTimestamp still Day 6's 1790609699, executed=canceled=false; `execute(0)` and the Timelock's execute still `TooEarly()` | state(0) raw=0x...04 -> 4 = Queued; proposals(0): canceled=false executed=false queued=true, tally=4.0000 B/0/0, data=setStakingRewardShareBps(600), salt=0xc338b2d3...30a0; operations(0x37dfdc53...5033): readyTimestamp=1790609699 (2026-09-28 15:34:59 UTC) executed=false canceled=false; Governor.execute(0) from F1 -> 0x085de625 = TooEarly(); Timelock.execute(op0) from the Governor -> 0x085de625 = TooEarly(); 496516 s (5 d 17 h 55 m 16 s) to go at the read; proposal 1 still Defeated | PASS |
| U8.2 | The Safe and its roles | owners F1, F2, F3, threshold 2, nonce 6 (four pause-drill transactions + T5 + T6), Safe 1.3.0; on the Timelock the Safe holds CANCELLER_ROLE and NOTHING else (no PROPOSER, no EXECUTOR, no ADMIN); the Governor's `guardian` == the Safe; the Governor holds PROPOSER, EXECUTOR and CANCELLER; the Timelock self-administers; getMinDelay 604800; guardianAuthorityExpiry the same on Timelock and Governor | owners=[0xD9dB15E2...fc16, 0xdFfeAEb8...687f, 0xacA4FaA9...0F9b], threshold=2, nonce=6, VERSION="1.3.0"; Timelock: safe CANCELLER=true PROPOSER=false EXECUTOR=false ADMIN=false; governor PROPOSER=true EXECUTOR=true CANCELLER=true; self CANCELLER=true ADMIN=true; getMinDelay=604800; guardianAuthorityExpiry=1883988338 on both (== Day 1) ; Governor.guardian=0x4253f80666E48a04CAbE4966Aa63035Dbb4f104F | PASS |
| U8.3 | The 2b invariant and the LP | the Timelock holds 0 BNB and 0 DMN; its LP unchanged since Day 1's close; the Safe holds 0 BNB and 0 DMN (payment=0 on both ExecutionSuccess: the executors paid their own gas) | Timelock: BNB=0 wei, DMN=0, LP=11497751703836292291632 wei (== Day 1 close); Safe: BNB=0 wei, DMN=0; signer BNB after the day: F1=0.49991, F2=0.04998, F3=0.04998; the two transactions cost 215661 gas in total at 0.1 gwei | PASS |
| U8.4 | Read back over eth_getLogs since Day 7's last block (132415117) | exactly 2 `Cancelled` on the Timelock (T5's, T6's), exactly 1 `ProposalCanceled` on the Governor (T5's, id 3), 0 `CallExecuted`, 0 `ProposalExecuted`, 0 new `CallScheduled` | Cancelled found=2 (0x86564200...ccb12 in block 132589551 tx 0x56babddc..., 0xd895606c...98e7d in block 132590593 tx 0x160c72ea...), ProposalCanceled found=1 (id 3, block 132589551), CallExecuted=0, ProposalExecuted=0, CallScheduled=0 -- over 4 chunks of 50000 blocks on publicnode, the 2 oldest (132415117-132515116, before the day) pruned/unreadable, the 2 holding the day readable; the archival endpoint refuses getLogs (-32005 limit exceeded); the storage reads of H4.7.4/U8.1 (executed=false on all three operations) settle the same question independently of the log service | PASS |

> **Scenario W, closed end to end on a public chain.** P-A was proposed
> by staker3 on 2026-09-15 22:54:30 UTC (a `setMaxTxAmount(type(uint256).max)`
> that removes the per-transfer cap), reached the 10 % quorum on its
> proposer's own 1.20 B FOR against a 0.64 B bar WITHOUT ANY TEAM VOTE
> (the holder cast nothing on it, Day 5), passed at voteEnd 2026-09-21
> 22:54:30 UTC on the clock alone, was queued into the Timelock at
> 23:35:11 UTC the same day (queue() is permissionless: anyone), and was
> stopped by the guardian at 2026-09-22 21:31:31 UTC -- 21 h 56 m 20 s
> into its 7-day delay, 6 d 02 h 03 m 40 s before it could have been
> executed -- with a single `Timelock.cancel(opId)` signed 2-of-3 (F3, F1),
> the Governor never called. The Governor reports the proposal Canceled
> anyway (H4.7.1) because state() reads the Timelock's flag (#26): the two
> contracts cannot disagree about whether P-A is alive. Its operation can
> no longer be executed by the EXECUTOR (`OperationNotReady`, H4.7.5), and
> the Safe, which stopped it, could not execute it either
> (`AccessControlUnauthorizedAccount`): the guardian is a brake, not a
> steering wheel. The cap it targeted is still 5 B (H4.7.7). The harmless
> twin P-B went the other way, through `Governor.cancel(3)`, and the
> Timelock's `Cancelled` and the Governor's `ProposalCanceled(3)` landed in
> the same transaction (H4.5.2): the atomic cross-cancel, observed.

### Findings of the day, recorded not fixed

1. **The Governor's struct flag and the Governor's state() can differ,
   by design, after a direct Timelock cancel.** `proposals(2).canceled` is
   false and will stay false unless someone calls `Governor.cancel(2)`
   (which would succeed, H4.7.6, and only converge the flag); `state(2)` is
   Canceled regardless. Anything that reads the struct's `canceled` field
   instead of `state()` -- an indexer, a dashboard, the monitor -- would
   report P-A as Queued. For `SPEC_MONITOR.md`: proposal state is
   `state(id)`, never the struct; a `Cancelled` on the Timelock is the
   URGENT signal for a queued proposal even when no `ProposalCanceled`
   follows. Contract behaviour as audited (#26).
2. **publicnode served both receipts this time**, where on Days 3-4 it
   returned null for the four pause transactions; identical to the
   archival copy field by field. The variance is the backend the
   load-balancer picks, not the chain. The archival endpoint in turn
   refuses `eth_getLogs` (`-32005 limit exceeded`) and publicnode caps a
   range at 50000 blocks and has pruned the two oldest chunks since Day 7
   (U8.4). Every claim above that a log service could carry is also made
   from storage (`operations`, `proposals`, `state`), which no backend
   prunes.
3. **The direct Timelock cancel is the cheaper one**: 92861 gas against
   122800 for the cross-cancel through the Governor, the difference being
   the Governor's own writes and events. Not a reason to prefer it -- the
   cross-cancel is what keeps the Governor's flags honest -- but the
   mainnet runbook can quote both.

**3 scenarios plus the untouched reads, 19 asserted rows: 19 PASS, 0 NOTE,
0 DEVIATION.** The harness signed nothing; the two transactions are the
Safe's, nonces 4 and 5, 215661 gas in total at 0.1 gwei. `git diff
audit-final -- src/` stays empty (this entry only READS `cancel`,
`state`, `operations`, `execute`).

The H4 drill is complete on Chapel: H4.1, H4.2, H4.4 (Days 3-4), H4.5,
H4.6, H4.7 (today); H4.3 (a pause left to lapse) is not run on the real
clock, by the 2026-08-28 decision. P-A and P-B are terminal: Canceled has
no path out in either contract, and nothing is ever signed for them
again (the optional `Governor.cancel(2)` flag convergence is not needed
and not planned). What remains is the campaign's own proposal: proposal 0
stays Queued with earliest execute **2026-09-28 15:34:59 UTC**, and the
H3.3b/H3.4 sitting (execute, then the first poke that pays the marketing
branch on a public chain) runs from that instant, not before. The Safe
will not cancel it.

## Day 9 -- Execute and the first poke at 600 (2026-09-28)

The last sitting of the governance cycle on the real clock, and the last
untested what-if of the campaign. The 7-day delay of queue(0) ended at
readyTimestamp; execute(0), signed by the holder, applies
setStakingRewardShareBps(600) through the Timelock (H3.3b). Then the fee
inventory is armed and a 1-wei direct transfer to the pair pokes the
automation (H3.4): with share 600 the marketing branch pays the
marketing wallet -- the Timelock -- for the first time on a public chain,
through its receive(). The split is verified wei-exact between the block
before the poke and the poke block, against the ethReceived the token
emits. The 2b invariant flips in this sitting: the Timelock's BNB is
verified, then recorded as the expected balance (lib.ps1).


### H3.3b -- The execute: proposal 0 applies setStakingRewardShareBps(600) through the Timelock; a second execute is refused

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| H3.3b.1 | Preflight from live state, before execute | chain 97; now >= readyTimestamp 1790609699; proposal 0 Queued (queued=true, executed=canceled=false); operation slot readyTimestamp == state file, not executed, not canceled; opId recomputed on-chain == Day 6's; proposal 1 Defeated, 2 and 3 Canceled; share 1000; marketingWallet == Timelock; stakingContract == staking; guardian roles as deployed; Timelock BNB 0, DMN 0; Timelock holds all LP but the 1000 burned | chain=97, block=133695759 ts=1790610032 (2026-09-28 15:40:32 UTC), ready since 333 s; state0=Queued queued=true executed=false canceled=false; op readyTimestamp=1790609699 executed=false canceled=false, opIdMatch=True; state1=Defeated state2=Canceled state3=Canceled; share=1000; marketingWallet=0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736; stakingContract=0xdB1C23eAAa306A7dbaD410E0aAa8eBDD249c62d1; token GUARDIAN_ROLE(Safe)=true, timelock CANCELLER_ROLE(Safe)=true, governor.guardian()=0x4253f80666E48a04CAbE4966Aa63035Dbb4f104F, guardianAuthorityExpiry=1883988338 (2029-09-13 10:05:38 UTC), token GOVERNANCE_ROLE(Timelock)=true; Timelock BNB=0 DMN=0; LP Timelock=11497751703836292291632 of totalSupply 11497751703836292292632 (2026-09-28 15:40 UTC) | - | PASS |
| H3.3b.2 | The holder calls execute(0) | receipt status 1, from == holder, to == governor, mined at ts >= readyTimestamp; proposals(0).executed true; state() == Executed (5); operations(opId).executed true; token.stakingRewardShareBps() == 600 | status=0x1, from=0x583982463da108879566868506cba32e7b023576, to=0x41f55dac95a028c58dd51fd72eec9101ed2ded05, block=133695792 (ts=1790610047 = 2026-09-28 15:40:47 UTC, 348 s after ready), gas=114198; executed=true, state=Executed (5); op executed=true canceled=false; share=600; receipt served by bsc-testnet.publicnode.com (2026-09-28 15:40 UTC) | 0x3f1b923136c95354ae8599c2641b55b32b3d3be8e0bfa487975656c1db4ab21b | PASS |
| H3.3b.3 | The events decoded from the execute receipt | exactly 3 logs: ParamsUpdated("stakingRewardShareBps", 600) from the token; CallExecuted(id == opId, target == token) from the timelock; ProposalExecuted(0) from the governor | logs=3; ParamsUpdated param="stakingRewardShareBps" value=600; CallExecuted id=0x37dfdc53dc643b59a0b35a54da5b8430ab82e9641615733ce3ce71e6862c5033 target=0x48bd45d02641e688f63bd5129272c30a8828ad0b; ProposalExecuted id=0 (2026-09-28 15:40 UTC) | 0x3f1b923136c95354ae8599c2641b55b32b3d3be8e0bfa487975656c1db4ab21b | PASS |
| H3.3b.4 | The stranger tries execute(0) a second time | refused by the Governor itself: AlreadyExecuted() (selector 0x0dc10197), the first check in execute(), before state() or the Timelock; no transaction mined | reverted with AlreadyExecuted; eth_call: cast : Error: server returned an error response: error code 3: execution reverted, data: "0x0dc10197" In C:\Users\Utente\Desktop\Daimon dao\script\chapel2b\D9-execute-poke.ps1:181 car:9 + $raw = (cast call $st.governor " (2026-09-28 15:40 UTC) | - | PASS |
| H3.3b.5 | After execute: nothing but the share moved | guardian roles unchanged; Timelock BNB 0 and DMN 0 (share 600 is live but no conversion has run yet); LP unchanged | token GUARDIAN_ROLE(Safe)=true, timelock CANCELLER_ROLE(Safe)=true, governor.guardian()=0x4253f80666E48a04CAbE4966Aa63035Dbb4f104F, guardianAuthorityExpiry=1883988338 (2029-09-13 10:05:38 UTC), token GOVERNANCE_ROLE(Timelock)=true; Timelock BNB=0 DMN=0; LP Timelock=11497751703836292291632 totalSupply=11497751703836292292632 (2026-09-28 15:40 UTC) | - | PASS |

### H3.4 -- The first poke at share 600: the marketing branch pays the Timelock for the first time -- 60/40 of the marketing share, wei-exact

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| H3.4.1 | The fee inventory vs the threshold, read before arming | recorded: the token's own DMN balance against minimumTokensBeforeSwap; fees 10/10/20 (tax 1%, liquidity 3% of which marketing 2%) | inventory=28103101012351284642331269 wei (0.0281 B) vs threshold 200000000000000000000000000 (0.2000 B), short by 0.1718 B; taxFee=10 liquidityFee=30 marketingFee=20 (2026-09-28 15:41 UTC) | - | PASS |
| H3.4.2 | Test sell: the stranger sells 0.02 B through the real router | the pair receives EXACTLY 96%; inventory += 3% plus the contract's reflection share (< 0.01% of it); router-initiated, so NO conversion: the Timelock still at 0 BNB | pair DMN +19200000000000000000000001 wei (96% = 19200000000000000000000000); inventory +600005745206697751342427 wei (3% = 600000000000000000000000, extra 5745206697751342427); BNB out of the pool=0.0040; Timelock BNB=0; sell gas=192611 (2026-09-28 15:41 UTC) | 0x6b7160d3c447f42879600e719f7e6d441250fb835e40e81890f78f2176c557dc / 0x2a66a75f3a39fbbbcba55a3d5de11dcf23d5583b16fb4e4bc01b2112cb72c54b | DEVIATION |
| H3.4.3 | Inventory armed by ordinary taxed transfers holder -> stranger (5.7300 B in 2 sends, each <= 3.00 B) | inventory >= minimumTokensBeforeSwap; harness necessity, recorded as such (as Day 1, H1.21): the stranger's 0.43 B and a 0.78 B-DMN pool cannot carry the ~5.7 B of taxed volume that 0.17 B of inventory needs as sells without moving the price by multiples -- on mainnet the volume is organic | inventory=200612151888499968774129235 wei (0.2006 B) vs threshold 200000000000000000000000000; +0.1719 B from 5.7300 B of volume (2026-09-28 15:41 UTC) | 0x678fa6924d25223d30e9b3a517ee9e0c831573aa26cef09586f9a3e36a68ae62 / 0x6ff458efbc3fbb1de378ed3d5b42f9389d76a980f9b8b8e1acd1ecf3e9bfd60f | NOTE |
| H3.4.4 | The stranger pokes (1 wei of DMN straight to the pair) at share 600 | receipt status 1; exactly ONE threshold-sized chunk converts (#28 budget): SwapAndLiquify(tokensSwapped == minimumTokensBeforeSwap, ethReceived > 0) emitted -- it is emitted AFTER require(ok1), so its presence proves the call to the Timelock returned true; the token's DMN falls by exactly the chunk between block N-1 and N | status=0x1, block=133695872, gas=299981, logs=12 (receipt from bsc-testnet.publicnode.com); SwapAndLiquify tokensSwapped=200000000000000000000000000 ethReceived=33161075612616959 wei (0.0331 BNB); inventory 200612151888499968774129235 -> 612151888499968774129235, consumed=200000000000000000000000000 (2026-09-28 15:41 UTC) | 0xa2625c564a27c6f4f76e955ca3ca4cf302fdcc965cdc14c2afd668e4c4f69738 | PASS |
| H3.4.5 | Where the BNB went, with stakingRewardShareBps == 600 -- wei-exact, block N-1 -> N | marketingEth = floor(ethReceived x 20 / 30); staking += floor(marketingEth x 600 / 1000) and RewardNotified(that amount) (not RewardReserved: stakers exist); TIMELOCK += marketingEth - toStaking via call{value} to its receive(); the token retains ethReceived - marketingEth (buyback); the three deltas sum to ethReceived | ethReceived=33161075612616959; marketingEth=22107383741744639; staking +13264430245046783 (expected 13264430245046783, RewardNotified=13264430245046783); TIMELOCK +8842953496697856 (expected 8842953496697856); token +11053691870872320 (expected 11053691870872320); sum=33161075612616959 (2026-09-28 15:41 UTC) | 0xa2625c564a27c6f4f76e955ca3ca4cf302fdcc965cdc14c2afd668e4c4f69738 | PASS |
| H3.4.6 | The Timelock's BNB balance, before and after the first payment it ever received from the token | 0 before (the invariant held through 27 checks); after == the marketing-wallet share of this one conversion; zero DMN before and after | BNB at block 133695871 = 0 wei; at block 133695872 = 8842953496697856 wei (0.0088 BNB); DMN after = 0 (2026-09-28 15:41 UTC) | 0xa2625c564a27c6f4f76e955ca3ca4cf302fdcc965cdc14c2afd668e4c4f69738 | PASS |
| H3.4.7 | The chunk against the pool it was sold into (as H1.24, recorded not judged) | recorded | chunk 0.2000 B against DMN reserve 0.7981 B = 2505 bps; BNB drawn 0.0331 of 0.1657; price 207686802 -> 132847432 wei/token, move -3603 bps (2026-09-28 15:41 UTC) | 0xa2625c564a27c6f4f76e955ca3ca4cf302fdcc965cdc14c2afd668e4c4f69738 | PASS |
| H3.4.8 | Closing reads: guardian, Timelock DMN, LP | guardian roles unchanged from preflight; Timelock DMN still 0; LP totalSupply and the Timelock's LP balance unchanged (the fee swap sells, it adds no liquidity); share still 600 | token GUARDIAN_ROLE(Safe)=true, timelock CANCELLER_ROLE(Safe)=true, governor.guardian()=0x4253f80666E48a04CAbE4966Aa63035Dbb4f104F, guardianAuthorityExpiry=1883988338 (2029-09-13 10:05:38 UTC), token GOVERNANCE_ROLE(Timelock)=true; Timelock DMN=0; LP Timelock=11497751703836292291632 (was 11497751703836292291632), totalSupply=11497751703836292292632 (was 11497751703836292292632); share=600 (2026-09-28 15:41 UTC) | - | PASS |
| H3.4.9 | The 2b invariant flips (lib.ps1): the Timelock's native must now EQUAL the sum of verified conversions; its DMN must stay 0 | state file timelockBnbExpected = 8842953496697856; Assert-Invariants passes in its new form | timelockBnbExpected=8842953496697856, Timelock BNB now=8842953496697856, invariant checks=33 (2026-09-28 15:41 UTC) | - | PASS |

### Day 9 status (2026-09-28) -- H3.3b and H3.4 closed on a public chain

> **H3.4.2, explained, recorded as DEVIATION of the harness, not of the
> contract.** The pair's DMN *reserve* grew by 96% + 1 wei. The sell
> was right, but the harness measured the pair's reserve, not its balance.
> Read at fixed blocks: at 133695837 (just before the sell) the pair
> held `778916844349680170575692965` DMN against a reserve of
> `...964`, last synced at 1789380611 (2026-09-14, Day 1). That 1 wei
> is Day 1's poke (H1.22): the poke's fee swap syncs the pair *before*
> the poke's own 1 wei lands, so the wei sits above the reserve until
> the next swap. The pool saw no swap for 14 days, and today's router
> sell swept it in. Measured by **balance**, the pair got exactly
> `19200000000000000000000000` = 96% of 0.02 B, with no deviation.
> Today's poke left a new stray wei the same way (block 133695872:
> balance `...966`, reserve `...965`). Harness lesson for mainnet
> runbooks and the monitor: a sell's received amount is `balanceOf(pair)`
> delta, never the reserve delta, whenever a poke has run since the last
> swap. `D9-execute-poke.ps1` is left as it ran.

> **H3.3b.4, the exact error.** The second `execute(0)` (stranger,
> gas estimation, no transaction mined) reverts with custom error
> `AlreadyExecuted()`, selector `0x0dc10197`. Its eth_call returns
> `execution reverted, data: "0x0dc10197"`. The Governor stops it
> itself, at the first line of `execute()`, before `state()` or the
> Timelock. (The row's observed text also carries the PowerShell
> error-record wrapper around cast's stderr. That is cosmetic.)

**H3.4, the numbers (poke `0xa2625c56...f69738`, block 133695872,
299981 gas):**

| leg | formula | wei | BNB |
|---|---|---|---|
| ethReceived (SwapAndLiquify) | swap of 0.2000 B | 33161075612616959 | 0.0332 |
| marketingEth | floor(ethReceived x 20 / 30) | 22107383741744639 | 0.0221 |
| staking (RewardNotified) | floor(marketingEth x 600 / 1000) = 60% | 13264430245046783 | 0.0133 |
| **Timelock** (receive()) | marketingEth - toStaking = 40% | **8842953496697856** | **0.0088** |
| token (buyback reserve) | ethReceived - marketingEth | 11053691870872320 | 0.0111 |

The three balance deltas between blocks 133695871 and 133695872 each
equal their formula and sum to ethReceived to the wei. The Timelock
went from **0 to 8842953496697856 wei**. The call to it succeeded:
receipt status 1, and `SwapAndLiquify` is emitted only after
`require(ok1)`. The automation did not block: exactly one
threshold-sized chunk (0.2000 B) was consumed. **H3.5 did not
trigger**: the Timelock's `receive()` accepts the marketing branch's
`call{value}` with the gas the token forwards, on a public chain.

### Findings of the day, recorded not fixed

1. **The stray poke wei** (above). The contract behaves as designed.
   The finding is about measurement, and it matters to anything that
   derives a trade size from reserves.
2. **The chunk is 25% of this pool.** The 0.2 B chunk against a 0.7981 B
   reserve is 2505 bps, and the price moved by -36.03% (207686802 ->
   132847432 wei/token). The pool is the Chapel one: 0.249 tBNB at
   open, 0.166 before this poke, already down from Day 1's -44.73%. Same
   reading as H1.24: the fixed 0.02%-of-supply chunk needs a mainnet pool
   deep enough that it is a small fraction of the DMN reserve. This is
   input for the liquidity decision, not a contract issue.
3. **The monitor's inversion is now due.** The first BNB from the token
   to the Timelock has landed. Under share 1000 this would be the
   anomaly. Under 600 it is the expected 40% leg. The harness invariant
   flipped in the same sitting (lib.ps1: `timelockBnbExpected` =
   8842953496697856, re-asserted: 33 checks). The monitor's
   `marketingBranch` setting should move to `{expectedShareBps: 600,
   onInbound: NOTIFY}` by hand, as planned (H3.3 of the plan). It stays
   manual on purpose.

**2 scenarios, 14 asserted rows: 12 PASS, 1 NOTE (H3.4.3: the arming
volume is a harness necessity, as Day 1's H1.21), 1 DEVIATION (H3.4.2,
harness measurement, explained above).** Signed today: execute (holder),
approve + sell (stranger), two arming transfers holder -> stranger
(3.00 B + 2.73 B), poke (stranger). That is six transactions.
`git diff audit-final -- src/` stays empty.

H3 is complete on Chapel: propose (Day 1), vote (Day 2), queue (Day 6),
execute and the first 60/40 poke (today). Proposal 0 is terminal
(Executed). With 1 Defeated and 2 and 3 Canceled, no proposal of this
campaign is alive. What remains is H5, the closing.

---

## Campaign closure (2026-09-28)

One day on a fork (2026-09-12), then nine sittings on BSC Chapel from
2026-09-14 to 2026-09-28: 14 real days, every state change a signed
transaction from an encrypted keystore or a 2-of-3 Safe with Ledgers, every
hash in this log, every value asserted read from mined state. Level 2 proved
the audited contracts on a public chain with the launch scripts of
2026-08-28. This mini-campaign proved the launch configuration those scripts
now carry. `src/` was never touched: the contracts exercised here are the
`audit-final` bytecode.

### What 2b proved (H0-H4)

| block | where | proven |
|---|---|---|
| H0 | fork, Day 0 | The six script changes, implemented and rehearsed: H0.1 `marketingWallet` defaults to the predicted Timelock (override loud, and refused on chain 56 since Day 1); H0.2 `setFees(10, 10, 20)` by the deployer's temporary GOVERNANCE_ROLE before the hand-over, asserted in phase 2 (20 -> 25 asserts); H0.3 two new post-broadcast checks (34 -> 36); H0.4 all LP to the Timelock as launch step 6, asserted from mined state; H0.5 the predecessor mock carries the real DMX 1.5B `_maxTxAmount`; H0.6 seven tests for it (180 -> 187), none of the 180 adapted. |
| H1 | Chapel, Day 1 | The launch order 1-11b on a public chain with those scripts. **36/36 post-broadcast checks from mined state** (H1.7, output verbatim). **Fees 10/10/20 -- 4% -- from the first block** (H1.5; setFees before the grant before the revoke, H1.5b); the test sell paid exactly 96% to the pair (H1.19). **`marketingWallet` == the Timelock from deploy**, the same prediction as the migration's treasury and governance, fulfilled four times by one address (H1.3, H1.4, H1.6). **All LP to the Timelock** in one published transaction: owner 0, deployer 0, Timelock == totalSupply - 1000 (H1.14). One pool (H1.15). First poke at share 1000: zero BNB to the Timelock (H1.23). |
| H1/H2 | Chapel, Day 1 | **The DMX maxTx finding, reproduced and resolved.** Reproduced: a 3B claim refused by the predecessor's own cap message before 11a (H2.2), nothing moved (H2.3); 11a raised the cap to the full supply, 11b opened the window LAST, and the same 3B cleared 1:1 to the wei (H2.6). Resolved at step 5: the launch-order gap of Day 0 (liquidity needs DMN before any claim is possible) is closed by giving the liquidity leg to the DMX owner, who is fee- and cap-exempt on DMX and claims ONLY the liquidity quota before the window opens (H1.10, H1.12: exact 1:1, 0.5530 B). The deployer and the DMX owner are two different wallets, as on mainnet. |
| H1 | Chapel, Day 1 | **The DMN 5B-cap finding and decision (c).** The planned 3-BNB opening does not fit the token's own 5B maxTx (6.66B gross at the DMX price). Decision (c): the largest single addLiquidityETH the cap allows -- 5B gross, 4.8B net, 2.2512 BNB at 4.69e-10 -- no parameter change, no exemption to any person; further depth from the treasury by proposal. Run at Chapel scale with the ratio kept: the pair received the net target +1 wei, price 468999999 vs 469000000 (H1.11, H1.13). |
| H3.1-H3.3 | Chapel, Days 1-9 | The first mainnet proposal on the real clock: propose (Day 1), vote with quorum from one staker (Day 2), queue with the 7-day floor exact (Day 6), **execute** after readyTimestamp, `stakingRewardShareBps` 1000 -> 600, a second execute refused with `AlreadyExecuted()` (Day 9, H3.3b). |
| H3.4 | Chapel, Day 9 | **The first 40% leg reached the Timelock wei-exact**: one poke, one threshold chunk, ethReceived 33161075612616959 -> staking 13264430245046783 (60%), Timelock 8842953496697856 (40%, via `receive()`, the first BNB it ever received), token 11053691870872320 (buyback); the three deltas sum to ethReceived. The marketing branch's `call{value}` to the Timelock did not revert: H3.5 was not triggered. |
| H4.1-H4.4 | Chapel, Days 3-4 | **The pause drill, with "Psy unreachable"**: two pauses and two unpauses through the Safe, each pause self-scheduled at +1209600 s to the second (#36); T3/T4 signed by F2 and F3 alone, F1's address in no field of either transaction (H4.4.5); the migration deadline credited the UNION of the windows, not their sum (+14 d 20 h 39 m 09 s for 4 h 14 m 24 s of pause). |
| H4.5-H4.7 | Chapel, Day 8 | **Both cancellation paths, and Scenario W closed end to end.** P-B through `Governor.cancel(3)`: the Timelock's `Cancelled` and the Governor's `ProposalCanceled` in one transaction. P-A -- the hostile proposal that passed on its proposer's votes alone, without any team vote, and was queued by a third party -- through `Timelock.cancel(opId)` directly, 21 h 56 m into its 7 days: `Governor.state(2)` reads Canceled on its own, neither operation can execute, the Safe cannot execute either, the cap P-A targeted is still 5B. |

The 2b invariant -- the Timelock receives no BNB and no DMN from the token
while the share is 1000 -- was asserted programmatically after every signed
harness transaction on Chapel: 27 checks at zero, then flipped in the same
sitting as the first payment to "the Timelock's BNB EQUALS the verified 40%
legs" and re-asserted: **33 checks** at close.

Rows, from this journal: Day 0 on the fork, 36 (35 PASS, 1 NOTE). Chapel,
Days 1-9: **123 rows -- 117 PASS, 3 NOTE, 3 DEVIATION**. The three
DEVIATION rows are harness-side, each explained under its row: an
expectation that ignored the inventory's reflection share (H1.16), a
matcher that missed the chain's exact message across a console line-wrap
(H2.2), a reserve-delta measurement taken where a balance delta was needed
(H3.4.2). Zero protocol deviations.

Closing gates, from this working tree at the commit that closes the
campaign:

| gate | result |
|---|---|
| src/ vs tag `audit-final` | `git diff audit-final -- src/` is empty: the bytecode deployed and exercised here is the audited source, untouched through the campaign |
| forge test | 26 suites, **187 tests passed**, 0 failed, 0 skipped (the 180 of `audit-final` + the 7 of H0.6) |
| post-broadcast verification on Chapel | 36/36, Day 1 (H1.7) |

### Findings carried forward

1. **The Safe web interface is not a source of truth; the chain is.** On
   Chapel it reported HTTP 422 / "failed" for transactions mined with
   status 0x1, and a queued transaction vanished from the other signers'
   view after an execution attempt. What is read aloud before confirming
   is the calldata; what settles "did it work" is the receipt (Days 3-4).
   For the mainnet runbook.
2. **MetaMask must have the connected Ledger's account selected.** With
   another account selected, signing fails ("does not belong to the
   connected device"); the fix is selecting the matching account, not
   reconnecting the device (Days 3-4). For the mainnet runbook.
3. **The Governor's struct flag `canceled` stays false after a direct
   Timelock cancel.** `proposals(2).canceled` is false while `state(2)`
   is Canceled, and stays so unless someone calls `Governor.cancel(2)`
   only to converge the flag (Day 8, H4.7.6). Proposal status is read
   from `Governor.state(id)`, never from the flag; a Timelock `Cancelled`
   is the URGENT signal for a queued proposal even when no
   `ProposalCanceled` follows. Contract behaviour as audited (#26). Now
   in `docs/SPEC_MONITOR.md` and `DAPP_SPEC.md`.
4. **Public RPC receipts and logs are pruned.** publicnode returned null
   receipts for mined transactions on Days 3-4 and served them on Day 8
   (the backend the load-balancer picks, not the chain); it caps
   `eth_getLogs` at 50000 blocks and prunes older chunks, and the archival
   endpoint refuses `eth_getLogs` (-32005). Every claim that mattered was
   also made from storage (`state`, `proposals`, `operations`, balances at
   fixed blocks), which no backend prunes.
5. **The poke's chunk-to-pool ratio, input for G1b.** The fee-swap chunk
   is fixed by the contract at 0.2B (0.02% of supply); the pool is not.
   Observed on Chapel: 34.54% of the DMN reserve, price -44.73% (Day 1,
   H1.24); 25.05%, price -36.03% (Day 9, H3.4.7). Arithmetic for mainnet
   at the decision-(c) pool: 4.17%, about -7.8% per conversion. The
   liquidity the treasury adds by proposal after launch is what brings
   that number down; the chunk moves only by `setMinimumTokensBeforeSwap`.

### Recorded honestly: what this campaign did not do as first written

- **Two proposals where one was intended** (H3.1.4): a crashed runner was
  resumed past a signed step and proposed again. Proposal 1 was never voted
  and lapsed to Defeated; the runners now refuse to resume past a signature.
- **The float claims were harness necessities** (H1.17, H3.4.3): 7B
  claimed by the owner and 5.73B of holder-to-stranger transfers to arm the
  inventory. On mainnet the owner claims only the liquidity quota (step 5a)
  and the volume that arms conversions is organic.
- **H1.6, the monitor in dry-run on the 2b addresses**, lives outside this
  repository (daimon-monitor, set `chapel-2b`, switched to
  `marketingBranch {600, NOTIFY}` after execute(0)); its alerts were not
  asserted as rows here, and none of this journal's claims depend on it.
  Its Timelock `Cancelled` is still sent as NOTIFY; finding 3 asks URGENT.

### What was not tested, and why

- **The 14-day pause lifting on the real clock (H4.3).** Not run, by the
  2026-08-28 operator decision that stands since Level 2: `setPaused(true)`
  always arms min(now + 14 days, guardianExpiry), so observing a lapse
  with no transaction would have frozen the token for two weeks and stopped
  the governance cycle. What Chapel did observe is the scheduling side of
  #36 to the second (both pauses at +1209600 s) and the migration credit;
  the self-termination is timestamp arithmetic, proven at Level 1 (E2) on
  the warped clock.
- **Mainnet-sized pool behaviour.** The Chapel pool opened at 0.249 tBNB,
  so each threshold chunk was a quarter to a third of it and moved the
  price by 36-45%. The mainnet columns (4.17%, about -7.8% per conversion
  at the decision-(c) pool) are constant-product arithmetic, not
  observation; slippage, arbitrage and the buyback on a pool of that depth
  are seen first at launch, with the monitor watching.

### Addresses at close (Chapel, chain 97, block 133698175, 2026-09-28 15:58:40 UTC)

```
DaimonV2 (token/proxy):  0x48BD45D02641e688f63bD5129272C30A8828ad0b   fees 10/10/20, share 600, maxTx 5 B, not paused
DaimonStaking:           0xdB1C23eAAa306A7dbaD410E0aAa8eBDD249c62d1   0.0523 BNB
DaimonGovernor:          0x41F55DAc95A028c58Dd51FD72eec9101ed2DEd05   0 Executed, 1 Defeated, 2 Canceled, 3 Canceled
DaimonTimelock/treasury: 0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736   = marketing wallet; 8842953496697856 wei BNB, 0 DMN, all LP, 12.1530 B mock DMX
DaimonMigration:         0x9c54e19bad8AcA0b7910C0E88BfBcAAbB249B718   totalMigrated 12.1530 B; effective deadline 1793256289 (2026-10-29 06:44:49 UTC)
Pair DMN/WBNB:           0x82E71914ED2Ef364C6C760e3D728e6DC610FD2b8   0.9981 B / 0.1326 tBNB; Timelock LP 11497751703836292291632 of 11497751703836292292632
Mock predecessor (DMX):  0xb0aA935f46354501d622C4A11a554CE226ADAE28   owner = oldowner, cap 1000 B, Timelock exempt
Guardian (test Safe):    0x4253f80666E48a04CAbE4966Aa63035Dbb4f104F   2 of 3, nonce 6, GUARDIAN_ROLE + CANCELLER_ROLE only
```

Keystores: the campaign wallets stay encrypted on the operator's machine;
the shared password file is deleted as the last step of the closing
session, after this journal, the merge and the tag are pushed. No key,
password or password path ever entered the repository.

**The 2b mini-campaign is closed.**
