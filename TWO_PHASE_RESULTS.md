# Two-phase deploy -- local proof (branch deploy/two-phase)

Proof runs for the two-phase deploy that closes Level 1 deviation A1.8: the
guardian expiry skew between the token (computed by `initialize()` in the
mined block) and the Timelock/Governor (constructor arguments fixed during
`forge script` simulation), and the broader fact that in-script asserts are a
simulation gate, not an on-chain one.

Harness: the Level 1 campaign harness (`script/campaign/`, brought over from
branch `campaign/level-1`), Anvil forking BSC testnet so the real PancakeSwap
V2 periphery serves `initialize()`. `Run-MainDeploy` now runs
`DeployPhase1.s.sol` then `DeployPhase2.s.sol`; addresses come from the state
file the scripts themselves maintain (`deployments/two-phase-97.json`).

Reference values from Level 1 (deviation A1.8, single-phase deploy, real
broadcast): token guardianExpiry = **1882278209**, timelock/governor
guardianAuthorityExpiry = **1882278205** -- a 4-second skew, invisible to
`_assertDecentralized()` because the assert ran in simulation.

The global invariant of the Level 1 campaign stays armed here too: the
marketing wallet receives nothing, ever, checked after every send.


## Follow-up: derived treasury + fee-exemption reorder

Two review findings addressed on the same branch, and every proof below
re-run from scratch against the updated scripts:

1. **The treasury is derived, never typed.** `DaimonMigration.treasury`
   (immutable, destination of every migrating holder's old tokens) is now
   the SAME predicted timelock address the migration's governance is bound
   to -- `TREASURY_ADDRESS` no longer exists. A separate treasury survives
   only as `TESTNET_TREASURY_OVERRIDE`: loudly logged, refused on chain 56
   (scenario N1 shows the refusal). The campaign's A-scenarios use that
   override (they assert against the separate keyless treasury); A1-2p and
   V1 run the mainnet-faithful derived path.
2. **The predecessor fee exemption moved to the end of the launch order.**
   Without it, claim() reverts with AmountMismatch (#29, proven in A0) --
   so between the phases no claim can occur, and the exemption is performed
   only after the post-broadcast verification is green. The harness mirrors
   this: Run-MainDeploy performs the exemption AFTER phase 2.

Assertion counts after the follow-up: phase 1 = 10, phase 2 = 20,
post-broadcast verification = 34.


### A1-2p -- Two-phase deploy on a live node: the A1.8 skew is gone, exactly

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| A1-2p.1 | Both phases broadcast against the live node | five contracts up, addresses recorded by the scripts own state file | token=0xE88995f41aE91eEF0c9Cb66ad23b5831d4702CCA, timelock=0x20211Cc856d7522412b8d39767Bf7a3f6719E50a, governor=0x52a097332b571ccF720FC02312cD4165e9BF87bA | PASS |
| A1-2p.2 | Guardian expiry read from the three live contracts | EXACT equality - phase 2 read the mined value and passed it verbatim | token=1882306187, timelock=1882306187, governor=1882306187 | PASS |
| A1-2p.3 | The expiry actually embedded in the phase-2 calldata | equals the live token value - in A1.8 this is exactly where the stale simulated value sat | calldata argument=1882306187, live token=1882306187 | PASS |
| A1-2p.4 | Launch compliance configuration | stakingRewardShareBps == 1000, set in phase 2 | 1000 | PASS |
| A1-2p.5 | Supply placement across the phase boundary | the entire supply in the migration, untouched by phase 2 | supply=1000.0000 B, in migration=1000.0000 B | PASS |
| A1-2p.6 | The phase-1 prediction came true | migration.governance (immutable, set in phase 1) IS the timelock deployed in phase 2 | migration.governance=0x20211Cc856d7522412b8d39767Bf7a3f6719E50a, timelock=0x20211Cc856d7522412b8d39767Bf7a3f6719E50a | PASS |
| A1-2p.7 | The migration treasury, read live | it IS the timelock: derived in phase 1 from the same prediction as the governance, fulfilled in phase 2 | migration.treasury=0x20211Cc856d7522412b8d39767Bf7a3f6719E50a, timelock=0x20211Cc856d7522412b8d39767Bf7a3f6719E50a | PASS |
| A1-2p.8 | How the treasury value came to be | no hand-typed input anywhere: the state file records treasuryOverridden=false | treasuryOverridden=False, env override present=no | PASS |
| A1-2p.9 | Marketing wallet after the full two-phase deploy | zero, as always | DMN=0 | PASS |

### V1 -- script/verify-deploy.ps1 against the live node: every invariant from mined state

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| V1.1 | Full verification run | every check green, exit code 0 | exit=0, tail: Post-broadcast verification -- chain 97 VERIFICATION PASSED: 34/34 checks green against live chain state. | PASS |

Full output of the verification, verbatim:

```
Post-broadcast verification -- chain 97
State file: C:\Users\Utente\Desktop\Daimon dao\deployments\two-phase-97.json


check                                  expected                                   observed                                   verdict
-----                                  --------                                   --------                                   -------
code at token                          present                                    present                                    PASS
code at timelock                       present                                    present                                    PASS
code at governor                       present                                    present                                    PASS
code at staking                        present                                    present                                    PASS
code at migration                      present                                    present                                    PASS
token: timelock holds GOVERNANCE_ROLE  true                                       true                                       PASS
token: deployer lacks GOVERNANCE_ROLE  false                                      false                                      PASS
token: deployer lacks DEFAULT_ADMIN    false                                      false                                      PASS
token: guardian holds GUARDIAN_ROLE    true                                       true                                       PASS
token: stakingRewardShareBps == 1000   1000                                       1000                                       PASS
token: stakingContract is the staking  0xCa901bb81b3467A1BF079003c9c5Bd41a4041891 0xCa901bb81b3467A1BF079003c9c5Bd41a4041891 PASS
token: marketingWallet as configured   0x000000000000000000000000000000000000a001 0x000000000000000000000000000000000000a001 PASS
token: migration is fee-exempt         true                                       true                                       PASS
timelock: self-administers             true                                       true                                       PASS
timelock: deployer lacks ADMIN_ROLE    false                                      false                                      PASS
timelock: deployer lacks PROPOSER_ROLE false                                      false                                      PASS
timelock: deployer lacks EXECUTOR_ROLE false                                      false                                      PASS
timelock: governor is proposer         true                                       true                                       PASS
timelock: governor is executor         true                                       true                                       PASS
timelock: guardian is canceller        true                                       true                                       PASS
timelock: governor is canceller        true                                       true                                       PASS
timelock: self-cancel role present     true                                       true                                       PASS
expiry: timelock == token (exact)      1882306186                                 1882306186                                 PASS
expiry: governor == token (exact)      1882306186                                 1882306186                                 PASS
staking: timelock is governance        true                                       true                                       PASS
staking: deployer is not governance    false                                      false                                      PASS
supply: totalSupply == INITIAL_SUPPLY  1000000000000000000000000000000            1000000000000000000000000000000            PASS
supply: all of it in the migration     1000000000000000000000000000000            1000000000000000000000000000000            PASS
migration: governance is the timelock  0x20211Cc856d7522412b8d39767Bf7a3f6719E50a 0x20211Cc856d7522412b8d39767Bf7a3f6719E50a PASS
migration: newDaimon is the token      0xE88995f41aE91eEF0c9Cb66ad23b5831d4702CCA 0xE88995f41aE91eEF0c9Cb66ad23b5831d4702CCA PASS
migration: oldDaimon as configured     0x7b331c59e5f9139923a06EA0B06CEa36cE9CF5d7 0x7b331c59e5f9139923a06EA0B06CEa36cE9CF5d7 PASS
migration: treasury as configured      0x20211Cc856d7522412b8d39767Bf7a3f6719E50a 0x20211Cc856d7522412b8d39767Bf7a3f6719E50a PASS
migration: treasury is the timelock    0x20211Cc856d7522412b8d39767Bf7a3f6719E50a 0x20211Cc856d7522412b8d39767Bf7a3f6719E50a PASS
token: pancake pair created            present                                    present                                    PASS



Guardian expiry raw values: token=1882306186 timelock=1882306186 governor=1882306186
VERIFICATION PASSED: 34/34 checks green against live chain state.

```
| V1.2 | Counter-proof: a state file with a wrong governor address | the verification fails loudly with a non-zero exit code | exit=5 | PASS |

### N1 -- Treasury override on BSC mainnet (chain 56): phase 1 refuses with nothing broadcast

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| N1.1 | Phase 1 with TESTNET_TREASURY_OVERRIDE set, on chain 56 | refused in simulation with the guard's own message | exit=1, message found=True | PASS |
| N1.2 | Was anything broadcast? | nothing: no chain-56 journal written, deployer nonce untouched | journal exists=False, nonce 23356 -> 23356 | PASS |

The refusal, verbatim from the forge output:

```
└─ ← [Revert] Phase1: TESTNET_TREASURY_OVERRIDE is not available on BSC mainnet (chain 56). The treasury IS the Timelock.
forge : Error: script failed: Phase1: TESTNET_TREASURY_OVERRIDE is not available on BSC mainnet (chain 56). The
+ CategoryInfo          : NotSpecified: (Error: script f...S the Timelock.:String) [], RemoteException
+ FullyQualifiedErrorId : NativeCommandError
```

### A0 -- Predecessor configuration (Zenith #29) - BLOCKING, with counter-proof

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| A0.1 | Deploy the predecessor, distribute the 1000 B model, exempt the TREASURY (not Migration), then run the real Deploy.s.sol | preflight applied before Migration exists; deploy completes | old=0x7b331c59e5f9139923a06EA0B06CEa36cE9CF5d7 migration=0x4cC96326eB2b9703c094CD8E78226881fC4eC8bc | PASS |
| A0.2 | Read the exemption flags on the predecessor | treasury exempt = true, Migration exempt = false | treasury=true, migration=false | PASS |
| A0.3 | team1 (NOT exempt) claims 10.00 B | treasury receives EXACTLY 10.00 B, no fee deducted | treasury delta = 10.0000 B | PASS |
| A0.4 | Check the new-token leg of the same claim | claimant receives exactly 10.00 B DMN, 1:1 | received = 10.0000 B | PASS |
| A0.5 | COUNTER-PROOF, throwaway state: exempt the Migration contract INSTEAD of the treasury | treasury exempt = false, Migration exempt = true | treasury=false, migration=true | PASS |
| A0.6 | team1 claims under the WRONG configuration | the fee IS deducted, the claim fails visibly (AmountMismatch), nothing is credited | reverted with AmountMismatch; treasury delta = 0.0000 B | PASS |

The counter-proof is the point: with the wrong exemption the predecessor deducts its 11% fee on the claimant->treasury leg (1.1000 B on a 10.0000 B claim), the treasury receives less than declared, and DaimonMigration's exact-delta check refuses to credit anything. The wrong configuration cannot pass silently - it stops the migration until it is fixed, which is why the checklist marks it BLOCKING.

### A2 -- Partial migration: 1:1 credit, old tokens out of circulation

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| A2.1 | tp1 (76.90 B of old) migrates 30.00 B | receives exactly 30.00 B DMN | 30.0000 B | PASS |
| A2.2 | tp1 old-token balance after the partial claim | 76.90 - 30.00 = 46.90 B left | 46.9000 B (was 76.9000 B) | PASS |
| A2.3 | Where the old tokens went | the treasury holds them: out of circulation, not burned | treasury +30.0000 B | PASS |
| A2.4 | Migration DMN reserve | down by exactly what it credited | -30.0000 B | PASS |
| A2.5 | Migration internal accounting | migratedAmount[tp1] = totalMigrated = 30.00 B | per-account=30.0000 B, total=30.0000 B | PASS |

### A3 -- Second claim by the same holder: the remainder, with no double counting

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| A3.1 | tp1 claims the remaining 46.90 B after the earlier 30.00 B | holds 76.90 B DMN in total, 1:1 across two claims | 76.9000 B | PASS |
| A3.2 | tp1 old balance | zero: fully migrated | 0.0000 B | PASS |
| A3.3 | Per-account accounting after two claims | migratedAmount[tp1] = 76.90 B, counted once, not twice | 76.9000 B | PASS |
| A3.4 | Protocol-wide total | totalMigrated = 76.90 B, matching the treasury old-token holding | total=76.9000 B, treasury=76.9000 B | PASS |
| A3.5 | tp1 tries a third claim with nothing left | fails: allowance and balance are both exhausted, nothing is credited twice | reverted | PASS |

### A4 -- Full migration in one call: exact 1:1

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| A4.1 | tp2 migrates its entire holding in one transaction | DMN received equals the old balance exactly, to the wei | old was 75.4180 B, DMN now 75.4180 B | PASS |
| A4.2 | tp2 old balance afterwards | zero | 0.0000 B | PASS |
| A4.3 | Treasury custody | holds exactly the migrated amount | 75.4180 B | PASS |

### A5 -- Everyone migrates: total migratable against the deploy script funding logic

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| A5.1 | Migration DMN funding, as the deploy script leaves it | the entire INITIAL_SUPPLY: the script funds it by making Migration the initialize() recipient | 1000.0000 B | PASS |
| A5.2 | Non-migratable old tokens | dead address plus the old contract itself, unreachable by any claim | dead=20.0000 B + contract=13.4700 B = 33.4700 B | PASS |
| A5.3 | Every reachable holder migrates 100 percent | total migrated = supply minus non-migratable = 966.53 B | 966.5300 B (expected 966.5300 B) | PASS |
| A5.4 | Was the funding sufficient | yes with room to spare: no claim can ever be refused for lack of DMN | funded 1000.0000 B vs claimed 966.5300 B, surplus left 33.4700 B | PASS |
| A5.5 | Global invariant after a full-supply migration | marketing wallet still at zero | DMN=0 | PASS |

The funding question has a structural answer rather than an arithmetic one: the script never computes a migration budget, it makes Migration the recipient of the entire INITIAL_SUPPLY in initialize(). Funding therefore cannot fall short - it exceeds the migratable amount by exactly the tokens nobody can claim (dead address and the old contract), which the post-deadline sweep later routes to the treasury.
