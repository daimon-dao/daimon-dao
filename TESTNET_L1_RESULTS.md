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

### A1 -- Full deploy through the real Deploy.s.sol (20 asserts, share at 1000, Migration funded)

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| A1.1 | Broadcast script/Deploy.s.sol against the node | the script completes; _assertDecentralized() (20 asserts) passes, otherwise the deploy aborts | deployed: token=0x4cc96326eb2b9703c094cd8e78226881fc4ec8bc staking=0x20211cc856d7522412b8d39767bf7a3f6719e50a timelock=0xca901bb81b3467a1bf079003c9c5bd41a4041891 governor=0x52a097332b571ccf720fc02312cd4165e9bf87ba migration=0xf2958240f43a36dc8b43227836030108f427651d | PASS |
| A1.2 | Compare the Migration address recorded in the token with the deployed one | identical: the CREATE-nonce precomputation held during a real broadcast | token.migrationContract=0xF2958240f43a36DC8b43227836030108f427651D vs deployed=0xf2958240f43a36dc8b43227836030108f427651d | PASS |
| A1.3 | Read stakingRewardShareBps after deploy | 1000 - the whole marketing share to stakers, zero operational, from block one | 1000 | PASS |
| A1.4 | Marketing wallet balances immediately after deploy | zero DMN, zero native - it has never been paid anything | DMN=0, native=0 | PASS |
| A1.5 | Migration funding | the entire INITIAL_SUPPLY sits in Migration; no EOA ever held it | migration=1000.0000 B, totalSupply=1000.0000 B | PASS |
| A1.6 | Token roles after the wiring | timelock governs, deployer holds nothing, guardian holds only the pause role | timelock.gov=true, deployer.gov=false, guardian.guard=true | PASS |
| A1.7 | CANCELLER roles (#26/#36) | guardian, governor and the timelock itself all hold it | guardian=true, governor=true, timelock-self=true | PASS |
| A1.8 | The single guardian expiry across the three contracts (#36) | one identical instant in token, timelock and governor | token=1882278209, timelock=1882278205, governor=1882278205 | DEVIATION |
| A1.9 | The DMN/WBNB pair created through the real PancakeSwap factory | a real pair contract exists at the recorded address | pair=0xC0D31E75cdA90ae01592964c1A3bdb501b5DacD8, code length=17334 | PASS |

The deploy under test is the production script, not the test fixture: had any of its twenty asserts failed, no deployment would exist to inspect. The CREATE-nonce precomputation - the part most likely to drift between simulation and broadcast - held.

#### DEVIATION A1.8 - the "single guardian expiry" is not single on a real deploy

**Observed.** After a real broadcast the three values disagree:
`token.guardianExpiry() = 1882278209`, while
`timelock.guardianAuthorityExpiry() = governor.guardianAuthorityExpiry() = 1882278205`.
The token's expiry is **4 seconds later** (3 s on a second run - the size of the
gap varies per run). `_assertDecentralized()` nevertheless passed: had it
failed, no deployment would exist.

**Why, proven rather than guessed** (`script/campaign/diag-expiry.ps1`):

- the Timelock's constructor calldata recorded in the broadcast journal ends
  with `0x7031493d` = `1882278205`. That number was fixed when `forge script`
  **simulated** the run;
- the token proxy was actually mined later, in block `127163920` at timestamp
  `1787670209`, and `initialize()` computed `guardianExpiry = 1787670209 +
  1095 days = 1882278209` from *that* block;
- the deploy script reads `token.guardianExpiry()` at runtime and passes it to
  the two constructors, so the two sides can only agree if the simulated
  timestamp equals the timestamp of the block the proxy lands in. On a live
  chain it never does.

**Why the assert cannot catch it.** `forge script` executes the body once in
simulation, collects the transactions, then broadcasts them. `_assertDecentralized()`
is a view call evaluated in the **simulation** context, where the token's expiry
and the constructor argument are the same number by construction. The assert is
structurally incapable of observing the skew it is meant to guard: it is not a
weak check, it is a check running against the wrong state.

**Impact.** Direction: the token's pause authority expires *after* the two
cancellation authorities, by the skew. Magnitude here: seconds out of 36 months;
on a public chain it is however long passes between forge's simulation and the
proxy's inclusion - seconds to minutes, still negligible in economic terms. What
is not negligible is the second half: any deploy-time guarantee asserted this
way - about a value derived at runtime from a contract deployed in the same
script - is unverified on-chain while appearing verified. The same blind spot
would cover a future assert of the same shape.

**Documentation touched by this.** THREAT_MODEL par.2.5 and the whitepaper
(par.5, par.8.6) state the expiry is "verified identical across the three at
deployment". On a real deploy that sentence is false as written.

**Which side is wrong.** Not the intent, and not the contracts: `src/` is
correct and does exactly what it says. The wrong side is the **expectation that
an in-script assert proves anything about post-broadcast chain state**, plus the
mechanism it guards - reading a just-initialized value at runtime and feeding it
to later constructors. A single explicit timestamp computed before any
deployment and passed to all three, or a verification pass run against the live
chain after the broadcast, would both close it. No fix attempted: the decision
is human.

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

### B0 -- Initial pool pricing (Zenith #17): price on what the pair RECEIVES, with counter-proof

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| B0.1 | Send 4.00 B DMN gross; the pair receives it net of the 5% fee | the pair's DMN reserve is the NET amount, 3.80 B - not the 4.00 B sent | reserve DMN = 3.8000 B, expected net = 3.8000 B | PASS |
| B0.2 | Pair BNB with the contribution computed on the NET receipt | opening price exactly 1 BNB = 1,000,000,000 DMN | implied = 1000000000 DMN/BNB (off by 0 bps) | PASS |
| B0.3 | COUNTER-PROOF, throwaway state: same 4.00 B gross, BNB computed on the GROSS | the pool opens at the WRONG price - fewer DMN per BNB than intended | implied = 950000000 DMN/BNB (off by 500 bps, i.e. DMN opens 5% too expensive) | PASS |
| B0.4 | Size limit on a single liquidity add | maxTxAmount caps the DMN leg: 5.00 B per transaction for a non-exempt provider | maxTxAmount = 5.0000 B; this run used 4.00 B gross to stay under it | NOTE |

Both halves land exactly where the checklist says they should. Pricing on the gross opens the pool 5.26% off - the mirror image of the 5% fee - and the error is silent: nothing reverts, the pool simply starts at a price nobody chose. Pricing on the net receipt lands on the intended ratio to the wei.

Operational note surfaced by running it: maxTxAmount is 5.00 B at deploy (0.5% of supply), so a realistic initial-liquidity position cannot be added in one transaction by a non-exempt provider - it has to be split into chunks, each paying the 5% fee and each needing its BNB leg computed on that chunk's NET receipt. Exempting the provider from fees instead would remove both the fee and the maxTx limit, and with them the #17 problem - but that exemption is a governance action with its own consequences, not a launch shortcut.

### B1 -- Ordinary wallet-to-wallet transfers: fee taken, passive holder grows by reflection

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| B1.1 | alice transfers 1.00 B to bob | bob is credited the amount net of the 5% fee (1% reflection + 4% to the contract) | credited 950047503.5152 vs net 950000000.0000 (delta includes bob's own reflection share) | PASS |
| B1.2 | A second transfer, bob back to alice | the contract's fee inventory grows by 4% of each transfer | inventory 480038402.5601 -> 560049203.4882 | PASS |
| B1.3 | carol never sends or receives anything during the two transfers | her balance GROWS anyway: reflection accrues to passive holders | 3800152006.0802 -> 3800228010.2604 (+76004.1801) | PASS |
| B1.4 | Total supply across the reflection | unchanged: reflection redistributes, it does not mint or burn | 1000.0000 B | PASS |
