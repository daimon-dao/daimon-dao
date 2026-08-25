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

### B2 -- Router sell above minimumTokensBeforeSwap: the sell passes, the automation stays put (Zenith #1)

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| B2.1 | Fee inventory before the sell | at or above minimumTokensBeforeSwap, so the automation is armed | inventory 0.5600 B vs threshold 0.2000 B | PASS |
| B2.2 | alice sells 1.00 B through the real PancakeSwap router | the sell goes through: she receives BNB | alice BNB +0.7587 | PASS |
| B2.3 | Did the fee swap fire during the sell? | NO - a router-initiated transfer skips the automation, so no DMN was converted | inventory 0.5600 B -> 0.6000 B (only grew, by the sell's own fee) | PASS |
| B2.4 | Did any BNB reach the token contract? | none: no conversion happened at all | contract BNB 0.0000 -> 0.0000 | PASS |
| B2.5 | Did the staking pool receive anything? | no: with nothing converted there is nothing to distribute | staking BNB 0.0000 -> 0.0000 | PASS |

This is the #1 fix behaving exactly as designed, and it is the behaviour the whitepaper now describes: ordinary sales through the router no longer convert fees, because doing so inside the router's own reserve window is what let a liquidity deposit be mispriced. The inventory simply accumulates until somebody pokes.

#### Harness note (not a protocol finding): the dev accounts are not EOAs on a public fork

The first B2 run showed alice losing her entire 10,000 BNB in a transaction
that sent zero value and burned 0.0000239 BNB of gas. `cast run` on that
transaction shows why:

```
- [9496] 0x3C44...93BC::fallback{value: 758783513405362144}()
   - [0] 0x1330d9...8869::fallback{value: 10000758751550905362144}()
```

Every one of the ten well-known Anvil/Hardhat dev addresses carries 23 bytes
of code on BSC testnet - `0xef0100` + address, an **EIP-7702 delegation** to a
sweeper that forwards the whole native balance the instant the account is
paid. The keys are public, so the accounts are farmed. Nothing to do with the
protocol: DMN transfers were unaffected (no callback), only native payouts.

The harness now clears that code (`anvil_setCode(addr, "0x")`) and restores
balances on the local fork at node start, so the roles behave as plain EOAs.
Worth carrying into Level 2: on a real Chapel deployment these addresses must
never be used for anything that receives BNB.

### B4 -- Three pokes in the same block: the #28 per-block budget holds

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| B4.1 | Inventory before, with several chunks available | well above one threshold, so a budget-free implementation could convert repeatedly | inventory=0.6000 B = 3 chunks | PASS |
| B4.2 | Three pokes from THREE DIFFERENT accounts, mined in one block | all three land in the same block | first poke block=0x7945e19, third poke block=0x7945e19 | PASS |
| B4.3 | How much was converted by three pokes in that block | ONE chunk, not three: the budget caps the aggregate per block, whoever calls | consumed = 0.2000 B, one chunk = 0.2000 B | PASS |
| B4.4 | A poke in the NEXT block | the budget rolls: another chunk converts, so this is pacing and not prohibition | consumed now = 0.4000 B | PASS |

### B5 -- Nobody ever pokes: fees accumulate, nothing is lost, only cadence degrades

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| B5.1 | Four rounds of transfers and router sells across 60 days, never a poke | the fee inventory only grows - nothing converts on its own | 0.5600 B -> 0.8000 B, i.e. 4 chunks waiting | PASS |
| B5.2 | Buyback BNB during those 60 days | none accrues, because nothing was ever converted | contract BNB 0.0000 -> 0.0000 | PASS |
| B5.3 | Does anything break? | no: transfers and sells keep working throughout, supply intact | totalSupply=1000.0000 B, every transfer and sell in the loop succeeded | PASS |
| B5.4 | The first poke after 60 days of silence | the accumulated inventory is intact and converts one chunk at a time | consumed 0.2000 B, still waiting 0.6401 B | PASS |
| B5.5 | Marketing wallet across the whole idle period | zero, as everywhere else | DMN=0 | PASS |

Nothing is lost by not poking: the fees sit in the contract as DMN and convert whenever somebody eventually sends a wei to the pair. What degrades is only the cadence of staking rewards and buyback pressure - the liveness dependency THREAT_MODEL par.8 describes, and it is a dependency on ANY address in the world bothering, not on a keeper.

#### Harness note: a pinned fork block does not stay available

Half-way through family B the runs began stalling. The cause was not the
protocol and not the machine: `state at block #127163903 is pruned` - the
public endpoint had dropped the state of the block pinned that morning, so
every fresh node died at genesis while partially-cached runs crawled. The
harness now resolves the pin at run time, caches it for the sitting and
re-resolves automatically when the endpoint stops serving it. Only the
PancakeSwap periphery is inherited from the fork - every Daimon contract is
deployed fresh per run - so the choice of recent block changes no result.

Worth carrying into Level 2: any campaign pinned to a public-chain block has
a shelf life measured in hours.

### C1 -- Stake at 30 days and at 365 days: voting power per the multipliers

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| C1.1 | alice stakes her balance on the 30-day option | voting power = amount x 1.0 | staked 3.8003 B -> vp 3.8003 B, expected 3.8003 B | PASS |
| C1.2 | bob stakes his balance on the 365-day option | voting power = amount x 4.0 | staked 3.8001 B -> vp 15.2006 B, expected 15.2006 B | PASS |
| C1.3 | Weight per unit staked, normalized | 1000 (1.0x) for the 30-day lock, 4000 (4.0x) for the 365-day one | alice=1000, bob=4000; raw ratio bob/alice = 3.9998x on unequal principals | PASS |
| C1.4 | Aggregates after both stakes | totals equal the sum of the parts | totalVotingPower=19.0009 B, totalStaked=7.6004 B | PASS |

Worth recording because it caught out the first version of this very test: alice and bob were sent an identical 4.00 B each, yet ended up staking 3.8003 B and 3.8001 B. In a reflection token two nominally identical transfers do not produce identical balances - the second sender's own reflection share has already moved between them. Any test comparing two holders head to head has to normalize per unit staked; the multipliers themselves are exact.

### C2 -- Withdraw before expiry: refused, and the position is untouched

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| C2.1 | alice tries to withdraw immediately after staking | refused: the lock has not expired | reverted with LockStillActive | PASS |
| C2.2 | Her position after the refused withdrawal | untouched - voting power and stake intact | vp = 3.8001 B | PASS |
| C2.3 | One day before expiry (29 of 30 days elapsed) | still refused - the boundary is respected to the second | reverted with LockStillActive | PASS |
| C2.4 | Just past 30 days | the withdrawal goes through, voting power returns to zero, principal comes back | vp=0.0000 B, balance=3.8001 B | PASS |

### C5 -- notifyRewardAmount with an awkward amount: strict pro-rata, no dust leaks

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| C5.1 | Weights before the distribution | bob carries 4x alice's weight for the same principal | alice vp=2.0000 B, bob vp=8.0000 B, total=10.0000 B | PASS |
| C5.2 | 3.141592653589793238 BNB notified | alice gets one fifth of it | alice 0.6283 vs ideal 0.6283, difference 1 wei | PASS |
| C5.3 | bob share of the same notification | four fifths, i.e. four times alice | bob 2.5132 vs ideal 2.5132, difference 6 wei; bob/alice = 4x | PASS |
| C5.4 | Everything accounted for | the shares sum to the notification bar a few wei of integer-division dust, which stays in the contract - never leaks out | sum=3141592653589793230 wei vs notified=3141592653589793238 wei, dust retained = 8 wei | PASS |
| C5.5 | alice claims | she receives what was pending, minus her own gas | pending was 0.6283, balance moved 0.6283 | PASS |
| C5.6 | The zero-staker reserve during a normal distribution | stays at zero: this path never touches it | 0.0000 BNB | PASS |

### D1 -- propose(): voting power and the quorum bar are frozen at creation

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| D1.1 | A proposal is created | its snapshot block is the block BEFORE its own - already sealed (#12) | created in block 127177397, snapshotBlock = 127177396 | PASS |
| D1.2 | The quorum denominator recorded with it | the aggregate voting power at that same sealed block | snapshotTotalVotingPower = 18.0000 B, live total = 18.0000 B | PASS |
| D1.3 | The quorum bps captured per proposal (#37) | the bps in force at creation, stored on the proposal itself | quorumBpsSnapshot = 1000, live quorumBps = 1000 | PASS |
| D1.4 | Someone stakes more AFTER the proposal exists | the live total moves, the proposal's denominator does not | live total 18.0000 B -> 22.0000 B, proposal still 18.0000 B | PASS |
| D1.5 | Proposal state right after creation | Pending: the one-day voting delay has not elapsed | Pending | PASS |

**Operational property surfaced while writing D1:** `maxTxAmount` (5.00 B at
deploy, 0.5% of supply) applies to **staking deposits** as well, because
`stake()` moves the tokens with an ordinary `transferFrom` and the staker is
not fee-exempt. A holder wanting to lock more than 5.00 B has to split it
across several transactions - each paying the transfer fee. The first version
of this scenario tried to stake 10.00 B in one call and the transaction never
came back; worth knowing before a whale tries it on mainnet.

### D4 -- queue, the 7-day timelock, execute - and what happens out of order

| step | action | expected | observed | verdict |
|---|---|---|---|---|

### D3 -- Vote and quorum: the bar is the snapshot, and later staking cannot move it

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| D3.1 | The bar this proposal must clear | 10% of the voting power that existed at the snapshot | quorum needed = 1.9000 B of 19.0000 B | PASS |
| D3.2 | Proposal state once the voting delay elapses | Active | Active | PASS |
| D3.3 | team1 votes in favour with its snapshot weight | its 16 B of weight is recorded, clearing the bar on its own | forVotes = 16.0000 B, needed = 1.9000 B | PASS |
| D3.4 | A whale stakes 16 B of fresh weight mid-vote | the live total jumps, this proposal's denominator does not | live 35.0000 B vs proposal denominator 19.0000 B | PASS |
| D3.5 | State at the end of the voting period | Succeeded: quorum met on the snapshot, for-votes ahead | Succeeded | PASS |

The whale that appeared mid-vote is exactly the actor the snapshot exists to neutralize: 16 B of new weight, arriving after the question was asked, changed neither the bar nor the tally.

### D4 -- queue, the 7-day timelock, execute - and what happens out of order

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| D4.1 | Proposal approved and out of voting | Succeeded, not yet queued | Succeeded | PASS |
| D4.2 | execute() without queue() | refused with its own precise error: the timelock is not optional | reverted with ProposalNotQueued | PASS |
| D4.3 | queue() by an address with no role at all | anyone may queue an approved proposal; state becomes Queued | Queued | PASS |
| D4.4 | execute() during the timelock delay | refused: the public reaction window is enforced by the Timelock itself | reverted | PASS |
| D4.5 | execute() after the seven days | the parameter actually changes on the token | taxFee 10 -> 10, buyback 10, marketing 20, liquidityFee 40 -> 30 (total 4%) | PASS |
| D4.6 | Proposal state afterwards | Executed | Executed | PASS |
| D4.7 | A second execute() of the same proposal | refused: no replay | reverted with AlreadyExecuted | PASS |

This is the historical proposal #0 replayed end to end - fees from 5% to 4% - through the real script's deployment: thirteen days of process compressed into warps, with every ordering guard refusing on its own terms.

### E1 -- Guardian pause and unpause

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| E1.1 | The guardian pauses the token | paused, with a window that ends at most MAX_PAUSE_DURATION out | isPaused=true, pauseUntil-now = 14 days, MAX_PAUSE_DURATION = 14 days | PASS |
| E1.2 | An ordinary transfer while paused | refused | reverted with ContractIsPaused | PASS |
| E1.3 | The permissionless burn while paused | also refused - the pause covers the supply accounting too (#5) | reverted | PASS |
| E1.4 | The guardian unpauses | transfers work again, and the window is cleared | isPaused=false, pauseUntil=0, bob now holds 0.9500 B | PASS |
| E1.5 | Anyone else trying to pause | refused: the role is the guardian's alone | reverted | PASS |

### E2 -- The pause window lapses on its own (Zenith #36)

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| E2.1 | Pause armed | a 14-day window, and the same 14 days credited to the migration clock | pauseUntil=1788885874, cumulativePauseSeconds=14 days | PASS |
| E2.2 | Thirteen days later, nobody has touched anything | still paused: the window has not run out | isPaused=true | PASS |
| E2.3 | Past the fourteenth day, still with NO transaction from anyone | the pause has lapsed by itself and transfers work | isPaused=false, and a transfer went through | PASS |
| E2.4 | The raw flag afterwards | still true - which is why interfaces must read isPaused(), not paused() | paused()=true vs isPaused()=false | PASS |
| E2.5 | The guardian renews the pause | a fresh window, and the credit grows again - every renewal is a visible transaction | credit 14 -> 28 days | PASS |

A pause cannot persist through inaction: keeping the token frozen takes a renewal every fortnight, each one an on-chain event. A lost guardian key stops mattering fourteen days later.

### E3 -- Both cancel paths on the same operation: the flags converge, nothing reverts (Zenith #26)

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| E3.1 | A proposal reaches the Timelock | queued on both sides: the Governor says Queued, the operation is scheduled | state=Queued, operation=1788799597 [1.788e9] false false | PASS |
| E3.2 | The guardian cancels directly at the Timelock | the Governor already reflects it: state reads Canceled, not Queued (#26 pt.4-6) | Canceled | PASS |
| E3.3 | Governor.cancel() on an operation already cancelled at the Timelock | succeeds: it sees the operation is cancelled and does NOT call cancel again (which would revert) | proposal.canceled=true, operation=1788799597 [1.788e9] false true | PASS |
| E3.4 | Executing it afterwards | impossible from either side | reverted | PASS |
| E3.5 | Cancelling the operation a second time at the Timelock | refused - which is exactly why the Governor had to check first | reverted with OperationAlreadyCanceled | PASS |

The invariant Poneder asked for holds on a chain: whichever path is used first, the two contracts never disagree about whether the operation can still execute, and the second path converges instead of reverting.

### E4 -- Already executed at the Timelock: Governor.cancel refuses (Zenith #26)

| step | action | expected | observed | verdict |
|---|---|---|---|---|
| E4.1 | Governance adds a second executor | a legitimate configuration - and the one that made this edge reachable | stranger holds EXECUTOR_ROLE = true | PASS |
| E4.2 | The second executor runs the operation straight at the Timelock | it takes effect on the token, while the Governor's own executed flag stays false | fees now 4%, proposal.executed flag = false | PASS |
| E4.3 | The guardian tries to cancel it afterwards | refused with AlreadyExecuted: the Governor reads the Timelock and will not call something cancelled that already happened | reverted with AlreadyExecuted | PASS |
| E4.4 | The proposal's canceled flag | still false - no divergence was created | canceled=false | PASS |

This is the exact configuration the finding described - an additional executor acting outside the Governor - and the fix holds where it counts: the Governor refuses to record as cancelled an action that already took effect on chain. The two contracts still agree.
