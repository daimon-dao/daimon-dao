# Chapel "2b" mini-campaign -- results (branch chapel/level-2b)

**Status: IN PROGRESS.** Day 0 is local (Anvil forking BSC Chapel); nothing
here has touched a public chain. Resuming after a crash or a new session =
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
