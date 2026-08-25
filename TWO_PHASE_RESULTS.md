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


### A1-2p -- Two-phase deploy on a live node: the A1.8 skew is gone, exactly

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| A1-2p.1 | Both phases broadcast against the live node | five contracts up, addresses recorded by the scripts own state file | token=0x4cC96326eB2b9703c094CD8E78226881fC4eC8bc, timelock=0xCa901bb81b3467A1BF079003c9c5Bd41a4041891, governor=0xF2958240f43a36DC8b43227836030108f427651D | PASS |
| A1-2p.2 | Guardian expiry read from the three live contracts | EXACT equality - phase 2 read the mined value and passed it verbatim | token=1882301575, timelock=1882301575, governor=1882301575 | PASS |
| A1-2p.3 | The expiry actually embedded in the phase-2 calldata | equals the live token value - in A1.8 this is exactly where the stale simulated value sat | calldata argument=1882301575, live token=1882301575 | PASS |
| A1-2p.4 | Launch compliance configuration | stakingRewardShareBps == 1000, set in phase 2 | 1000 | PASS |
| A1-2p.5 | Supply placement across the phase boundary | the entire supply in the migration, untouched by phase 2 | supply=1000.0000 B, in migration=1000.0000 B | PASS |
| A1-2p.6 | The phase-1 prediction came true | migration.governance (immutable, set in phase 1) IS the timelock deployed in phase 2 | migration.governance=0xCa901bb81b3467A1BF079003c9c5Bd41a4041891, timelock=0xCa901bb81b3467A1BF079003c9c5Bd41a4041891 | PASS |
| A1-2p.7 | Marketing wallet after the full two-phase deploy | zero, as always | DMN=0 | PASS |



### V1 -- script/verify-deploy.ps1 against the live node: every invariant from mined state

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| V1.1 | Full verification run | every check green, exit code 0 | exit=0, tail: Post-broadcast verification -- chain 97 VERIFICATION PASSED: 33/33 checks green against live chain state. | PASS |

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
token: stakingContract is the staking  0x52a097332b571ccF720FC02312cD4165e9BF87bA 0x52a097332b571ccF720FC02312cD4165e9BF87bA PASS
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
expiry: timelock == token (exact)      1882301575                                 1882301575                                 PASS
expiry: governor == token (exact)      1882301575                                 1882301575                                 PASS
staking: timelock is governance        true                                       true                                       PASS
staking: deployer is not governance    false                                      false                                      PASS
supply: totalSupply == INITIAL_SUPPLY  1000000000000000000000000000000            1000000000000000000000000000000            PASS
supply: all of it in the migration     1000000000000000000000000000000            1000000000000000000000000000000            PASS
migration: governance is the timelock  0xCa901bb81b3467A1BF079003c9c5Bd41a4041891 0xCa901bb81b3467A1BF079003c9c5Bd41a4041891 PASS
migration: newDaimon is the token      0x4cC96326eB2b9703c094CD8E78226881fC4eC8bc 0x4cC96326eB2b9703c094CD8E78226881fC4eC8bc PASS
migration: oldDaimon as configured     0x7b331c59e5f9139923a06EA0B06CEa36cE9CF5d7 0x7b331c59e5f9139923a06EA0B06CEa36cE9CF5d7 PASS
migration: treasury as configured      0x000000000000000000000000000000000000A002 0x000000000000000000000000000000000000A002 PASS
token: pancake pair created            present                                    present                                    PASS



Guardian expiry raw values: token=1882301575 timelock=1882301575 governor=1882301575
VERIFICATION PASSED: 33/33 checks green against live chain state.

```
| V1.2 | Counter-proof: a state file with a wrong governor address | the verification fails loudly with a non-zero exit code | exit=5 | PASS |
