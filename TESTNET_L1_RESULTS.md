# Testnet campaign — Level 1 (local Anvil, logical sequences)

**Status: IN PROGRESS.** Resuming after a crash or a new session = **start
from the first scenario not yet committed** in this file. Every scenario is
committed and pushed on `campaign/level-1` the moment it finishes, so
whatever appears below is done and verified; whatever is missing is not.

## What this campaign is

The 180 unit tests prove the functions work. This level proves the
**sequences** hold. Three audit findings (#12, #35, #28) were compositions of
individually-legitimate calls, invisible to unit tests by construction. The
checkpoint system, the guardian's three expiring authorities, the atomic
cancel edges, the poke model and the `stakingRewardShareBps = 1000` launch
configuration had never run on a chain before this.

## Harness

| piece | choice |
|---|---|
| Chain | Anvil forking **BSC testnet** at pinned block `127163903` (chain id 97) |
| Why a fork | the real PancakeSwap V2 router/factory live at the addresses `Deploy.s.sol` uses by default: the pool, the sells and the poke run against real periphery, not a mock |
| Deploy under test | the **real `script/Deploy.s.sol`**, broadcast against the node — not the `StackDeployer` test fixture. The deploy order, the precomputed Migration address, the `setStakingRewardShareBps(1000)` call and `_assertDecentralized()` (20 asserts) are themselves under test |
| Predecessor | `script/campaign/CampaignOldDaimon.sol` — a new file; `src/` is untouched. Fee disabled only when sender OR recipient is exempt, exemptions owner-gated (the real DMX semantics), 11% fee |
| Time | Anvil RPC only (`evm_increaseTime`, `anvil_mine`) — never by editing contracts |
| Runners | `script/campaign/*.ps1`, one per scenario, each rebuilding state on a fresh node |

### Roles — distinct accounts, never mixed

`deployer`, `guardian`, `alice`/`bob`/`carol` (stakers), `team1`/`team2` +
`tp1`/`tp2` + four silent third parties (migrating holders), `stranger`
(permissionless actions: the poke, queue, execute). The marketing wallet and
the treasury are **keyless constant addresses** — they can never sign, which
is itself part of the test.

### Old-token distribution modelled (1,000 B total)

| bucket | amount | addresses |
|---|---|---|
| Team | 427.12 B | team1, team2 (213.56 B each) |
| Third parties | 453.99 B | tp1 76.90 B (top holder) + 5 x 75.418 B |
| In pool | 85.42 B | pool-sim address |
| Non-migratable | 33.47 B | dead 20.00 B + old contract 13.47 B |

Migratable by construction = 1,000 - 33.47 = **966.53 B**. Scenario A5 checks
this against the deploy script's own funding logic.

## The global invariant

Asserted **programmatically after every single step of every scenario**, by
the runner, not by eye:

- the marketing wallet has received **nothing, ever** — `balanceOf(DMN) == 0`
  and native balance unchanged from genesis;
- `totalSupply() >= 21_000_000_000e18` (the floor);
- Governor and Timelock never disagree about an operation's state;
- nothing leaves the Timelock except through an executed proposal.

A single violation stops the campaign.

---

# Results


### A0 -- Predecessor configuration (Zenith #29) - BLOCKING, with counter-proof

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| A0.1 | Deploy the predecessor, distribute the 1000 B model, exempt the TREASURY (not Migration), then run the real Deploy.s.sol | preflight applied before Migration exists; deploy completes | old=0x7b331c59e5f9139923a06EA0B06CEa36cE9CF5d7 migration=0xf2958240f43a36dc8b43227836030108f427651d | PASS |
| A0.2 | Read the exemption flags on the predecessor | treasury exempt = true, Migration exempt = false | treasury=true, migration=false | PASS |
| A0.3 | team1 (NOT exempt) claims 10.00 B | treasury receives EXACTLY 10.00 B, no fee deducted | treasury delta = 10.0000 B | PASS |
| A0.4 | Check the new-token leg of the same claim | claimant receives exactly 10.00 B DMN, 1:1 | received = 10.0000 B | PASS |
| A0.5 | COUNTER-PROOF, throwaway state: exempt the Migration contract INSTEAD of the treasury | treasury exempt = false, Migration exempt = true | treasury=false, migration=true | PASS |
| A0.6 | team1 claims under the WRONG configuration | the fee IS deducted, the claim fails visibly (AmountMismatch), nothing is credited | reverted with AmountMismatch; treasury delta = 0.0000 B | PASS |

The counter-proof is the point: with the wrong exemption the predecessor deducts its 11% fee on the claimant->treasury leg (1.1000 B on a 10.0000 B claim), the treasury receives less than declared, and DaimonMigration's exact-delta check refuses to credit anything. The wrong configuration cannot pass silently - it stops the migration until it is fixed, which is why the checklist marks it BLOCKING.
