# Manual tests on BSC Testnet — Daimon DAO

Executed on 2026-07-08 (night, Italian time). Explorer: https://testnet.bscscan.com

Reference deploy (2026-07-08, all verified on BscScan):

| Contract | Address |
|---|---|
| DaimonV2 (proxy) | `0xf9a4d8b6ae6e37f198443e9855e3788119c94202` |
| DaimonStaking | `0x2f2135885617cd226214cf8fd3b945fddaea3606` |
| DaimonTimelock | `0x6a98fd0c0306672e4abfbe90fc303726022427f5` |
| DaimonGovernor | `0xe2445551f1d6c487e6cfb48f8621ccfb4d919c52` |
| DaimonMigration | `0x4c6f45b0148534296d8f9660eba5cc3598855bb2` |
| MockOldDaimon | `0xf5de50ae742df53b5b6a6bf5189f64a9d16157cc` |

Wallets involved:

| Role | Address |
|---|---|
| Deployer / guardian / treasury (testnet) | `0x3863962B17F322a8bbF8427f14D85094Db623A50` |
| Wallet B (test, throwaway) | `0x59B1AB91c8c85D01CcC3bf16A14fA7549F98DA35` |
| Wallet C (test, throwaway) | `0x0BD5122544515f2f9051f172BA9F74E290a1F984` |

Design note: on this testnet deployer = treasury, so the migration must be
tested from a third wallet — a claim by the deployer would have a
treasury-delta of zero and revert with `AmountMismatch` (intended
protection).

Setup (funding from the deployer):
- 0.05 tBNB to B — `0x5445b78b0cdf78b68b55634227a1e659073bd34b2afe86eb4e0b1b3832816077`
- 0.03 tBNB to C — `0x0911ea08fc0c0d004af8bf51ab864c047bfcc1cf68fff6f9f99747b108a1e2ff`
- 20,000,000 old DMN to B — `0xce14cc06f5551639abbd7d0f4b407e7db4f128ee4f88095dc33111de6598004e`
  (no fee: the sender/treasury is excluded in the mock)

---

## Test 1 — 1:1 Migration ✅

**What was tested**: approve of the old token + `claim(20M)` from wallet B;
verification of the 1:1 ratio on the new DMN and of the old tokens arriving in
the treasury.

| Step | Tx |
|---|---|
| `approve(migration, 20M)` on MockOldDaimon (from B) | `0x96ea721f36b9392b2562e4daad7254c36d32660c68fd416eca46a3cf7fe678a6` |
| `claim(20M)` on DaimonMigration (from B) | `0xf1e5c9b117fe938de721a25dc0e003f50f121e4dbffadaa022bc6e126eb9d594` |

**Result**: PASS.
- DMN received by B: `20,000,000.000000000000000000` — **exactly 1:1**, zero fee (migration excluded).
- Old tokens in the treasury: from 980M to **1,000M** (+20M exactly).
- `totalMigrated` = 20M.

**Anomalies**: none.

---

## Test 2 — Transfer with 5% fee and reflection to idle holders ✅

**What was tested**: a B→C transfer of 1,000,000 DMN (expected 5% fee: 1%
reflection + 4% to the contract), then a C→deployer transfer of 400,000 DMN
with B idle, to verify that B's balance grows on its own (reflection).

| Step | Tx |
|---|---|
| B→C 1,000,000 DMN | `0x22511bdc5afed8ceff8d505ffee9ec0d51ce1625cf681fd280baafaf71021a71` |
| C→deployer 400,000 DMN (B idle) | `0x130db1697dc6d187a9c0c7d37ab3d66cacd11a4429b65803c51a816c7ffbb4d1` |

**Result**: PASS.
- C received `950,000.0095…` = exactly 95% + the reflection share of its own tx.
- The token contract accumulated `40,000.0004…` = 4% liquidity fee.
- The deployer received `380,000.0015…` = 95% of 400k.
- **Reflection to idle B**: balance from `19,000,000.190000001900000019`
  to `19,000,000.266000002964000030` → **+0.076 DMN**, which matches the
  theory: 4,000 DMN of tax × (B's 19M / 1T of supply) = 0.076.

**Anomalies**: 1 (not the contract's). The first re-read of B's balance right
after C's tx showed it unchanged: it was **stale state from the RPC node**
`data-seed-prebsc-1`. A re-read a few seconds later on two different nodes gave
the same updated value. Lesson: after a tx, wait a block or query two nodes
before concluding.

---

## Test 3 — Staking: voting power 1x vs 4x, binding lock ✅

**What was tested**: a stake of 1,000,000 DMN at 30d (1x multiplier, lockId 0)
and one of 500,000 DMN at 365d (4x, lockId 1); early withdraw of lock 0.

| Step | Tx |
|---|---|
| `approve(staking, 2M)` | `0x421ca87e1209aaf60d0446f25629c1f5b98d97538f35251110263c84c652cc4a` |
| `stake(1M, option 0)` 30d 1x | `0x9eadcaff58d61aceb8b5dafcb5cb4bd8d60af35ea0538833f6ca588b2d0e831d` |
| `stake(500k, option 3)` 365d 4x | `0xa348f6ba29a29259937518466b5c92e8678b182e03e69f77b586349a68d86b7e` |
| `withdraw(0)` early | no tx: revert at gas-estimation stage |

**Result**: PASS.
- `votingPower(B)` = **exactly 3,000,000 DMN** (1M×1 + 500k×4). No fee on the
  stakes (staking is excluded from fees): precise accounted amounts.
- `totalVotingPower` = 3M.
- Early withdraw: revert with selector `0xba8dbe4c` = **`LockStillActive()`**,
  as expected. Lock 0 will be withdrawable from **2026-08-07**, lock 1 from
  **2027-07-08**.

**Anomalies**: none.

---

## Test 4 — Governance: propose now, vote/queue/execute on schedule ⏳

**What was tested**: immediate creation of proposal #0 — `setFees(10, 10, 20)`
on the token (total fee from 5% to 4%) — to start the clock; an immediate vote
attempt (must fail due to the voting delay).

| Step | Tx |
|---|---|
| `propose(token, 0, setFees(10,10,20), "Fee reduction…")` from B (vp 3M ≥ threshold 1000) | `0xa6e465fb70da2b587f8ab7795a22cfc7c29bc984d571020260178b6af2cb5035` |
| `castVote(0, 1)` immediate | no tx: revert `0x66b6cb4a` = **`VotingClosed()`** ✅ (1-day voting delay respected) |

Proposal #0 created at timestamp `1783467501` (2026-07-07 23:38:21 UTC).

**Calendar** (Italian time = UTC+2):

| Phase | From | Command |
|---|---|---|
| **Vote** | Jul 09 01:38 → Jul 14 01:38 | `cast send 0xe2445551f1d6c487e6cfb48f8621ccfb4d919c52 "castVote(uint256,uint8)" 0 1 --private-key (Get-Content .testwallets\walletB.key) --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545` |
| **Queue** (anyone) | after Jul 14 01:38 | `cast send 0xe2445551f1d6c487e6cfb48f8621ccfb4d919c52 "queue(uint256)" 0 --private-key (Get-Content .testwallets\walletB.key) --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545` |
| **Execute** | 7 days after the queue (≈ Jul 21 01:38) | `cast send 0xe2445551f1d6c487e6cfb48f8621ccfb4d919c52 "execute(uint256)" 0 --private-key (Get-Content .testwallets\walletB.key) --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545` |
| **Final check** | after the execute | `cast call 0xf9a4d8b6ae6e37f198443e9855e3788119c94202 "taxFee()(uint256)" --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545` → expected 10 (and buybackFee 10, marketingFee 20) |

The proposal state is queryable at any time:
`cast call 0xe2445551f1d6c487e6cfb48f8621ccfb4d919c52 "state(uint256)(uint8)" 0 --rpc-url …`
(0 Pending, 1 Active, 2 Defeated, 3 Succeeded, 4 Queued, 5 Executed, 6 Canceled)

**Partial result**: PASS (propose + delay enforcement). Vote/queue/execute to
be completed on schedule.

**Anomalies**: none.

---

## Test 5 — Guardian: pause and resume ✅

**What was tested**: `setPaused(true)` from the guardian (= deployer on
testnet), transfer blocked during the pause, `setPaused(false)`, transfer
restored.

| Step | Tx |
|---|---|
| `setPaused(true)` | `0x2ed41803dcbc82f342b98e60fe81df9f2bb9f5c7b6b9354ad3e53f6bd57e7765` |
| transfer B→C 1,000 DMN while paused | no tx: revert `0x6d39fcd0` = **`ContractIsPaused()`** ✅ |
| `setPaused(false)` | `0x7af6de32919e19b871590471a9c5eb5f10a53b39013785bf4c862fdb714e52fd` |
| transfer B→C 1,000 DMN after resume | `0xe6ebcd06dc761c15510a2eb4f4cd0c4ec6b25e636c769aa65a252f485c989aa0` ✅ |

**Result**: PASS. `paused()` was `true` during the block and the exact same
transfer went through after the resume.

**Anomalies**: none.

---

## Test 6 — Full burn cycle (Plan B) ✅

_Executed on 2026-07-17. Plan B: the testnet pool is too thin to trigger the
autonomous internal buyback (it requires the contract's BNB balance > 1,
unreachable with faucet tBNB), so the buyback branch was reproduced manually
with a purchase toward the dead address — the exact same mechanics as
`_buyBackAndBurn`. The autonomous fee swap, instead, was triggered on the real
chain._

**What was tested**: creation of real liquidity on the PancakeSwap testnet
pair, fee accumulation beyond `minimumTokensBeforeSwap` (200M DMN), triggering
of the autonomous fee swap with BNB distribution to marketing + staking, then
burn of the supply toward the floor.

Setup:
- Deployer → B: 900M old Daimon `0x0697e67fa330366050ba82e9e3933904a1980ef2f19cd4580e0891f8ab8ac166`
- Deployer → B: 0.4 tBNB `0x71cd3d70cce3331d7ca299cddad033fb54688fefc0ba0d63cd4db851b161ad41`
- B migrates 900M → DMN: approve `0xf30ba28107af7ce2408b11081b4505e90c37841ccda338ef58e689afb1733f9a`, claim `0x44228f91a7520026a2d9278e6c84b2f48d89e5b259f9c17f55e7295c8c5cb2b7`
- Pool liquidity: 60M DMN + 0.3 tBNB `0xc709a21f3e944aec2c0d09f5d90080d4f746b195d6f0536d485a056bcb2d3202`

Fee accumulation (B↔C ping-pong, 7 hops until it exceeds 200M):
`0x07c76a6f…`, `0x2aa563c9…`, `0x9c7bdd8c…`, `0xf8d73005…`, `0x457004ec…`,
`0x5fbced54…`, `0x29c38fde94c68e56ff0a0dc3df6dd1e1d7c1968daf1937d5a2827369d156b1ef`

**Autonomous fee-swap trigger** (sell C→pair) — `0xdfb46263409a3dd7bcf424749bed84c0f51079b599bc4b5db10ee1553ec28739`:
- 200M DMN of fee swapped for **0.2334 tBNB**
- marketing wallet: **+0.0467 tBNB** (0.3675 → 0.4142)
- staking: **+0.0700 tBNB** of rewards distributed to stakers
- the contract retains **0.1167 tBNB** as a buyback reserve

**Burn**:
- buy from the pool → dead address (0.015 tBNB): **+44.79M DMN to the dead address** — `0xc46363ba7bb54246e3056bcfa4933f8353e35b01e149d0d418efa4ac540a2e5f`
- `burnDeadBalanceToFloor()`: **totalSupply 1000.000B → 999.955B** — `0xd3e3a6f334878f5ac59ee0b74a47a964ae795d9bb153a01c3e800176695cfb79`
- **44,785,811 DMN burned** from the supply, dead address zeroed

**Result**: PASS. The autonomous fee swap works on the real pool (marketing and
staking paid in real tBNB); `burnDeadBalanceToFloor` really reduces the
supply; the dashboard shows the burned tokens and the deflation bar moved.

**Anomalies**: 1 (orchestration, not the contract's). The first trigger
attempt was launched from wallet B, which the ping-pong had left with a 0
balance (the last hop was B→C): the fee swap succeeded but the subsequent
transfer of the 1000 DMN from B underflowed on `_rOwned[B] -= rAmount` (B did
not have the tokens). Located with a fork test and re-triggered from C (which
held the DMN). No contract defect.

---

## Test 7 — Multi-wallet reward claim with wei-exact reconciliation ✅

_Executed on 2026-07-18/19. Three wallets with different voting power claimed
their BNB rewards from the dApp; complete accounting verification downstream._

**Reward source** — a single `notifyRewardAmount`, coming from the autonomous
fee swap of Test 6: **0.070008014335556812 BNB**
(tx `0xdfb46263409a3dd7bcf424749bed84c0f51079b599bc4b5db10ee1553ec28739`,
block 119,840,962, 18/07 13:19:31). At the moment of the notify:
`totalVotingPower` = 6.3M (B 3M, deployer 0.3M, new wallet 3M).

**Claim operations** (chronological order, verified via `cast receipt`):

| Wallet | Voting power | BNB claimed (exact) | Tx | When |
|---|---|---|---|---|
| New `0x8bd3…B491` | 3,000,000 | 0.033337149683598481 | `0x5792a79ca050b3f6d049cdbc3b514ceb6f76b02a92ca170d1a497d5d9d492315` | 18/07 18:38:03 |
| Deployer `0x3863…3A50` | 300,000 | 0.003333714968359848 | `0xa26d2df8794cc63d1475781a68536505b9fbaf98f903a0990ced9660d8a2cc9b` | 18/07 23:49:44 |
| B `0x59B1…DA35` | 3,000,000 | 0.033337149683598481 | `0x30f9e441089fe3785b4a9536cd64395c5cac41873ba2ea77b228a41576730691` | 18/07 23:50:27 |

**Wei-exact reconciliation** (invariant: in = claimed + pending +
undistributed + dust):

```
in (notify)                70008014335556812 wei
claimed (sum of 3 claims)  70008014335556810 wei
residual pending (all)                     0
undistributedRewards                       0
dust                                       2 wei
contract BNB balance                       2 wei  == dust ✓
```

The 2 residual wei are entirely explained: each claim computes
`floor(vp × rewardPerVotingPowerStored / 1e27)` and the three integer
divisions truncate 2 wei in total, which stay in the contract as dust.
**No unexplained discrepancy.**

**Proportionality**: the two wallets with identical vp (3M) claimed the same
amount to the wei; the deployer with vp = 1/10 (300k) claimed exactly 1/10 (to
within 1 wei of floor). Reward ∝ voting power ✓.

**Result**: PASS. The dApp updated balances and pending without a refresh
(automatic refetch after confirmation), and the contract's accounting closes
exactly.

**Operational note — getLogs on free BSC testnet nodes**: `eth_getLogs` is
effectively unavailable on all the free RPCs tried (Binance data-seed: -32005
limit exceeded even on a single block; drpc: internal/range errors;
Ankr/zan/publicnode: require an API key). The event reconstruction here was
done from contract state + `cast receipt` on the hashes provided by the
wallets. For mainnet: the dApp's event list (proposals, claims, etc.) will
require a paid RPC with getLogs or a dedicated indexer — already noted in the
dApp README as phase-2 work.

---

## Test 8 — Economic proof after execute: transfer with the 4% fee ✅

**Goal**: to prove that the execute of proposal #0 (21/07, tx
`0x5aa519a9884d24037f0cb903f3565f1a9e5e87529e5d4c1baa3f0c054302fe5f`) changed
the real economic behavior of the token, not just the getters.

**On-chain fees at the time of the test**: taxFee=10, buybackFee=10,
marketingFee=20 → `liquidityFee = buyback + marketing = 30`. Fees are in
per-mille: the total on a transfer = tax (10) + liquidity (30) = **40/1000 =
4%** (before the execute: 10+20+20 = 50/1000 = 5%).

**Test transfer** (2026-07-22, block 120637060): 1,000,000 DMN from wallet C
(`0x0BD5…F984`) to a new wallet (`0x8bd3…B491`) — tx
`0x347f849deab46e715575b9d0211cde2f53b6b46a83569233e1943b27c79baf63`.
Wallet-to-wallet: the autonomous swap cannot trigger (only on `to == pair`),
clean numbers by construction.

**Wei-exact reconciliation** (balances read with cast before/after):

```
Transfer event emitted            960000000000000000000000  = exactly 960,000 (96%)
sender C delta       −999994017140047554240496
  = −1,000,000 exact + 5982859952445759504 of reflection (≈5.98 DMN)
recipient delta      +960000079607264774839738
  = +960,000 exact + 79607264774839738 of reflection (≈0.0796 DMN)
contract delta       +30000114407223598371936
  = +30,000 exact (liquidityFee 3%) + reflection (the contract is a holder)
deployer delta (third party, uninvolved)  +688173113391125 (pure reflection ✓)
totalSupply          UNCHANGED (999955214188332986683725989731 before and after)
```

- **Total fee = 40,000 DMN out of 1,000,000 = exactly 4%** ✓ (10,000 reflected
  to holders + 30,000 accumulated in the contract).
- **Split**: tax 1% → reflection (verified below); buyback 1% + marketing 2% →
  the 30,000 in the contract (the buyback/marketing division happens at the
  swap, pro-rata `marketingFee/liquidityFee`, unchanged).
- **Net to the recipient = exactly 960,000 = amount − 4%** ✓ (with the
  pre-execute 5% it would have been 950,000).
- **1% reflection verified on third-party holders**: the deployer, uninvolved
  in the transfer, gains 688173113391125 wei; the gain/balance ratio
  (≈1.00004×10⁻⁸) matches tFee/reflectable-supply (10,000 / ~999.955B) and is
  the same rate for all sampled wallets (computed on post-move balances, per
  RFI math).

**Result**: PASS. The governance → timelock → execute → **real economic
effect** cycle is proven to the wei.

---

## Test 9 — Proposal #2: sweep of unclaimed DMN (in progress) ⏳

**Goal**: a REAL governance cycle with a post-deadline effect — after the
migration closes (2026-08-07 01:08:39) the DAO, via the Timelock, recovers the
never-claimed DMN to the treasury.

**Proposal #2** (on-chain id = 2):
- **target**: `0x4c6f45b0148534296D8F9660ebA5cC3598855Bb2` (DaimonMigration)
- **calldata**: `0xc44337b4` = `sweepUnclaimed()` (no arguments)
- **description**: "Proposta #2 — Sweep dei DMN non riscattati verso la
  treasury DAO dopo la chiusura della migrazione (7/08). Include le reflection
  accumulate dal contratto." (on-chain, proposer-authored — not translated)
- **proposer**: wallet B (`0x59B1…DA35`, vp 3,000,000)
- **creation**: tx `0x67b41be1ac4ab7ce3804ae24b6e1b1b50dfcb427834840286f3b9a14f3aceaa2`
  (block 120654407, status success)

**Preconditions verified on-chain before creating**:
- `migration.governance` = Timelock (`0x6a98…27f5`) → the execute via the
  timelock is allowed to call `sweepUnclaimed`. ✓
- `sweepExecuted` = false; the migration contract holds **~999.12B unclaimed
  DMN** (the amount that will end up in the treasury). ✓
- `sweepUnclaimed()` reverts with `MigrationStillOpen()` while
  `block.timestamp <= migrationDeadline` → the execute can only fall **after**
  07/08 01:08:39. ✓ (a contract-level guarantee, not just a schedule)

**Exact calendar** (VOTING_DELAY 1d, VOTING_PERIOD 5d, timelock 7d):

| Phase | Date/time (IT) | Notes |
|---|---|---|
| Creation | **2026-07-22 19:00:32** | done (state = Pending) |
| Vote OPENS (voteStart) | **2026-07-23 19:00:32** | before this, `castVote` reverts `VotingClosed` |
| Vote CLOSES (voteEnd) | **2026-07-28 19:00:32** | 5-day window |
| Queue (after voteEnd) | **07/28 → 07/31 01:08:39** | must be done by 07/31 01:08 to align the timelock with the deadline |
| Timelock ready | queue + 7d | if queued 07/28 → 08/04; if queued 07/31 01:08 → 08/07 01:08 |
| **Execute (sweep)** | **right after 08/07 01:08:39** | possible only once the migration deadline has passed |

Note on the margin: the execute falls **after 08/07 01:08:39 in any case**
(gated by the contract). If queued by 07/31 01:08:39 the timelock is ready
exactly at the deadline → margin ≈ 0. If queued earlier (e.g. right at the end
of voting, 07/28), the timelock is ready a few days early but the sweep stays
blocked until the deadline: the execute date does not change (08/07), only the
"In timelock" countdown shows ready ahead of time.

### ⚠️ REQUIRED FUTURE ACTIONS (on schedule)

1. **VOTE — ~2026-07-23 19:00** (as soon as it opens): `castVote(2, 1)` (Yes)
   from wallet B. **Without this vote proposal #2 does not reach quorum**
   (630K out of ~6.3M vp at the snapshot) and the sweep is skipped. Wallet B
   alone (3M) is enough.
2. **QUEUE — after 07/28 19:00, by 07/31 01:08**: `queue(2)` (anyone).
3. **EXECUTE — after 08/07 01:08:39**: `execute(2)` → sweep to the treasury.

**Current state**: PENDING (voting not yet open). To be completed per the
calendar above.

---

## Test 10 — Pre-freeze adversarial round (Foundry) ✅

The last targeted round before the freeze, on what adds value beyond the
audit. Executed as Foundry tests against the real contracts
(`test/Adversarial.t.sol`, 14 tests). Full suite green: **74 tests, 0
regressions**.

**Area 1 — Snapshot / whale.** Voting power acquired at a timestamp
**strictly after** a proposal's snapshot **does not count**: a whale with 2e9
of vp staked after the snapshot has `votingPowerAt(snapshot) = 0` and
`castVote` reverts `InsufficientVotingPower`. Nuance: staking at the exact same
timestamp counts, but it requires the same block as creation; since EVM block
timestamps are strictly increasing, whoever reacts to an already-mined
proposal is always in a later block → excluded. **Not exploitable.**

**Area 2 — Boundary values.** All correct: stake 1 wei → vp 1; migration
`claim(0)` reverts `ZeroAmount`, `claim(1 wei)` is 1:1; `burnDeadBalanceToFloor`
lands **exactly** on `MIN_SUPPLY` and never below (repeated is a no-op);
timelock `execute` at **ready−1s** reverts `TooEarly`, at **ready exact**
passes. *Limit note:* the stake per single tx is capped by `maxTxAmount`
(0.5% of supply = 5B DMN) — staking huge amounts must be split across multiple
txs (anti-dump by design).

**Area 3 — Perverse incentives (game theory).** Two findings:
- **Finding 1 (FIXED pre-freeze).** `state()` counted the quorum on
  `for + against + abstain`: an **against** vote could push a proposal over
  quorum and **pass** it, while staying silent denied it — a perverse
  incentive to not vote rather than oppose. **Fix:** quorum on `for + abstain`
  (against excluded, aligned with OpenZeppelin). The test that found the
  finding now demonstrates the correct behavior (with for 8% < quorum 10% and
  against 4% → **Defeated**); a companion test confirms that abstain still
  counts (for 8% + abstain 4% = 12% → **Succeeded**). dApp updated
  accordingly. Commit `cc551ba`.
- **Finding 2 (ACCEPTED as a design choice).** Voting power **does not decay**
  after the lock expires: the full vp (up to 4×) and reward share are kept
  until `withdraw`. It rewards historical lockers, differs from ve-tokens
  (Curve). No loss of funds. Documented in THREAT_MODEL.md §3.6 as a conscious
  v1 trade-off; a possible decay is phase-2 material via governance.

**Area 4 — Reflection edge.** Coherent accounting: conservation within dust
after taxed transfers; the dead address (the only reward-excluded account)
uses the `_tOwned` path and burn-to-floor stays wei-coherent. **Structural
strength:** no runtime exclude/include-from-reward function exists — only
`deadAddress`, immutable from init. The whole RFI "exclusion-toggle" bug class
is **absent by construction**.

**Result:** PASS. One finding fixed (quorum), one accepted and documented (vp
no-decay); snapshot, boundary and reflection solid.

---

## Summary

| # | Test | Result |
|---|---|---|
| 1 | 1:1 migration with treasury | ✅ PASS |
| 2 | 5% fee + reflection to idle holders | ✅ PASS (stale-RPC note) |
| 3 | Voting power 1x/4x + lock | ✅ PASS |
| 4 | Governance propose + delay | ✅ PASS — vote Jul 9, queue Jul 14, execute from Jul 21 |
| 5 | Guardian pause | ✅ PASS |
| 6 | Burn cycle (autonomous fee swap + supply burn) | ✅ PASS (Plan B) |
| 7 | Multi-wallet reward claim + wei-exact reconciliation | ✅ PASS |
| 8 | Economic proof after execute (4% fee) | ✅ PASS |
| 9 | Proposal #2 sweep (post-deadline governance cycle) | ⏳ IN PROGRESS — created, vote opens 07/23 19:00 |
| 10 | Adversarial round (snapshot, boundary, incentives, reflection) | ✅ PASS — Finding 1 fixed, Finding 2 accepted |

The test wallet keys B and C are in `.testwallets/` (excluded from git): they
are still needed for the future actions of proposal #2 (vote 07/23, queue
after 07/28, execute after 08/07) — **do not delete them before then**.
